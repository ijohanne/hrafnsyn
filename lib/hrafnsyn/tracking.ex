defmodule Hrafnsyn.Tracking do
  @moduledoc """
  Durable tracking state, search, and historical routes.
  """

  import Ecto.Query, warn: false

  alias Hrafnsyn.Ingest.Observation
  alias Hrafnsyn.Repo
  alias Hrafnsyn.Tracking.{Track, TrackPoint}

  @topic "tracking:updates"
  @default_active_window_minutes 20

  def topic, do: @topic

  def list_active_tracks(opts \\ []) do
    minutes = Keyword.get(opts, :minutes, @default_active_window_minutes)
    limit = Keyword.get(opts, :limit, 2_000)
    query_string = Keyword.get(opts, :query, "")

    Track
    |> where([track], track.observed_at >= ago(^minutes, "minute"))
    |> apply_query(query_string)
    |> order_by([track], desc: track.observed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_track(id), do: Repo.get(Track, id)

  def recent_points(track_id, hours) do
    TrackPoint
    |> where([point], point.track_id == ^track_id)
    |> where([point], point.observed_at >= ago(^hours, "hour"))
    |> order_by([point], asc: point.observed_at)
    |> limit(5_000)
    |> Repo.all()
  end

  def recent_log_entries(track_id, limit \\ 50) do
    TrackPoint
    |> where([point], point.track_id == ^track_id)
    |> order_by([point], desc: point.observed_at)
    |> limit(^limit)
    |> Repo.all()
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

    {:ok, touched_ids}
  end

  defp upsert_track(source, observation) do
    attrs =
      observation
      |> Observation.to_track_attrs()
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
          latitude: Map.get(attrs, :latitude),
          longitude: Map.get(attrs, :longitude),
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
end
