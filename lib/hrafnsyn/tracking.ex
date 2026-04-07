defmodule Hrafnsyn.Tracking do
  @moduledoc """
  Durable tracking state, search, and historical routes.
  """

  import Ecto.Query, warn: false
  alias Ecto.Adapters.SQL

  alias Hrafnsyn.Ingest.Observation
  alias Hrafnsyn.Repo
  alias Hrafnsyn.Tracking.{Track, TrackPoint}

  @topic "tracking:updates"
  @default_active_window_minutes 20

  def topic, do: @topic

  def list_active_tracks(opts \\ []) do
    opts
    |> active_tracks_query()
    |> Repo.all()
  end

  @spec search_active_tracks(String.t() | nil, keyword()) :: [struct()]
  def search_active_tracks(query, opts \\ []) do
    case normalize_search(query) do
      "" ->
        []

      normalized ->
        opts
        |> Keyword.put(:query, normalized)
        |> active_tracks_query()
        |> Repo.all()
    end
  end

  @spec resolve_active_track(String.t() | nil, keyword()) ::
          {:ok, struct()} | {:error, :blank_query | :not_found | :ambiguous}
  def resolve_active_track(query, opts \\ []) do
    case normalize_search(query) do
      "" ->
        {:error, :blank_query}

      normalized ->
        tracks = search_active_tracks(normalized, opts)
        exact_matches = Enum.filter(tracks, &exact_search_match?(&1, normalized))

        case exact_matches do
          [track] -> {:ok, track}
          [] -> resolve_unique_partial_match(tracks)
          _many -> {:error, :ambiguous}
        end
    end
  end

  def get_track(id) do
    Track
    |> where([track], track.id == ^id)
    |> with_coordinates()
    |> Repo.one()
  end

  def active_counts(minutes \\ @default_active_window_minutes) do
    grouped_counts =
      Track
      |> where([track], track.observed_at >= ago(^minutes, "minute"))
      |> group_by([track], track.vehicle_type)
      |> select([track], {track.vehicle_type, count(track.id)})
      |> Repo.all()
      |> Map.new()

    planes = Map.get(grouped_counts, "plane", 0)
    vessels = Map.get(grouped_counts, "vessel", 0)

    %{
      total: planes + vessels,
      planes: planes,
      vessels: vessels
    }
  end

  def recent_points(track_id, hours) do
    TrackPoint
    |> where([point], point.track_id == ^track_id)
    |> where([point], point.observed_at >= ago(^hours, "hour"))
    |> with_coordinates()
    |> order_by([point], asc: point.observed_at)
    |> limit(5_000)
    |> Repo.all()
  end

  def recent_log_entries(track_id, limit \\ 50) do
    TrackPoint
    |> where([point], point.track_id == ^track_id)
    |> with_coordinates()
    |> order_by([point], desc: point.observed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def recent_route_stats(track_id, hours) do
    track_id = Ecto.UUID.dump!(track_id)

    cutoff =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-(hours * 3_600), :second)
      |> NaiveDateTime.truncate(:second)

    sql = """
    SELECT
      observed_at,
      ST_Distance(lag(location) OVER (ORDER BY observed_at), location)::float8 AS segment_distance_meters
    FROM track_points
    WHERE track_id = $1::uuid
      AND observed_at >= $2::timestamp
      AND location IS NOT NULL
    ORDER BY observed_at ASC
    """

    case SQL.query(Repo, sql, [track_id, cutoff]) do
      {:ok, %{rows: rows}} ->
        observed_times = Enum.map(rows, &hd/1)

        distance_meters =
          Enum.reduce(rows, 0.0, fn [_observed_at, segment_distance], acc ->
            acc + (segment_distance || 0.0)
          end)

        %{
          distance_meters: distance_meters,
          observed_seconds: observed_span_seconds(observed_times)
        }

      _other ->
        %{distance_meters: 0.0, observed_seconds: 0}
    end
  end

  def ingest_batch(source, observations) do
    touched_ids =
      observations
      |> Enum.reduce([], fn observation, acc ->
        with {:ok, normalized} <- Observation.new(observation),
             {:ok, track} <- upsert_track(source, normalized),
             {:ok, _point} <- insert_track_point(track, source, normalized) do
          [track.id | acc]
        else
          _ -> acc
        end
      end)
      |> Enum.uniq()

    if touched_ids != [] do
      Phoenix.PubSub.broadcast(Hrafnsyn.PubSub, @topic, {:tracks_updated, touched_ids})
    end

    :telemetry.execute(
      [:hrafnsyn, :ingest, :batch],
      %{
        observations: length(observations),
        touched_tracks: length(touched_ids)
      },
      %{
        source_id: source.id,
        vehicle_type: Atom.to_string(source.vehicle_type)
      }
    )

    {:ok, touched_ids}
  end

  defp upsert_track(source, observation) do
    attrs =
      observation
      |> Observation.to_track_attrs()
      |> put_location()
      |> Map.merge(%{
        latest_source_id: source.id,
        latest_source_name: source.name,
        search_text:
          observation
          |> Observation.search_fields()
          |> Track.derive_search_text()
      })

    %Track{}
    |> Track.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          latest_source_id: source.id,
          latest_source_name: source.name,
          display_name: Map.get(attrs, :display_name),
          callsign: Map.get(attrs, :callsign),
          registration: Map.get(attrs, :registration),
          country: Map.get(attrs, :country),
          category: Map.get(attrs, :category),
          status: Map.get(attrs, :status),
          destination: Map.get(attrs, :destination),
          location: Map.get(attrs, :location),
          speed: Map.get(attrs, :speed),
          heading: Map.get(attrs, :heading),
          altitude: Map.get(attrs, :altitude),
          observed_at: Map.get(attrs, :observed_at),
          search_text: Map.get(attrs, :search_text),
          last_payload: Map.get(attrs, :last_payload),
          updated_at: DateTime.utc_now(:second)
        ]
      ],
      conflict_target: [:vehicle_type, :identity],
      returning: true
    )
  end

  defp insert_track_point(track, source, observation) do
    attrs =
      observation
      |> Observation.to_point_attrs()
      |> put_location()
      |> Map.merge(%{
        track_id: track.id,
        source_id: source.id,
        source_name: source.name,
        payload: Map.get(observation, :last_payload)
      })

    %TrackPoint{}
    |> TrackPoint.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:track_id, :source_id, :observed_at]
    )
  end

  defp apply_query(query, ""), do: query
  defp apply_query(query, nil), do: query

  defp apply_query(query, search) do
    wildcard = "%" <> String.trim(search) <> "%"

    where(
      query,
      [track],
      ilike(track.search_text, ^wildcard)
    )
  end

  defp active_tracks_query(opts) do
    minutes = Keyword.get(opts, :minutes, @default_active_window_minutes)
    limit = Keyword.get(opts, :limit, 2_000)
    query_string = Keyword.get(opts, :query, "")

    Track
    |> where([track], track.observed_at >= ago(^minutes, "minute"))
    |> apply_query(query_string)
    |> with_coordinates()
    |> order_by([track], desc: track.observed_at)
    |> limit(^limit)
  end

  defp with_coordinates(query) do
    select_merge(query, [record], %{
      latitude: fragment("ST_Y((?)::geometry)", record.location),
      longitude: fragment("ST_X((?)::geometry)", record.location)
    })
  end

  defp put_location(attrs) do
    latitude = Map.get(attrs, :latitude)
    longitude = Map.get(attrs, :longitude)

    case {latitude, longitude} do
      {lat, lon} when is_number(lat) and is_number(lon) ->
        Map.put(attrs, :location, %Geo.Point{coordinates: {lon * 1.0, lat * 1.0}, srid: 4326})

      _other ->
        attrs
    end
  end

  defp resolve_unique_partial_match([track]), do: {:ok, track}
  defp resolve_unique_partial_match([]), do: {:error, :not_found}
  defp resolve_unique_partial_match(_tracks), do: {:error, :ambiguous}

  defp exact_search_match?(track, query) do
    track
    |> searchable_values()
    |> Enum.any?(fn value -> normalize_search(value) == query end)
  end

  defp searchable_values(track) do
    [
      track.identity,
      track.display_name,
      track.callsign,
      track.registration,
      track.destination,
      track.country
    ]
  end

  defp normalize_search(nil), do: ""

  defp normalize_search(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp observed_span_seconds([]), do: 0

  defp observed_span_seconds([first | rest]) do
    last = List.last(rest, first)
    NaiveDateTime.diff(last, first, :second)
  end
end
