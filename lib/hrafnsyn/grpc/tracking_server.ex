defmodule Hrafnsyn.GRPC.TrackingServer do
  @moduledoc false

  use GRPC.Server, service: Hrafnsyn.V1.TrackingService.Service

  alias Hrafnsyn.Collectors.Config, as: CollectorConfig
  alias Hrafnsyn.GRPC.Helpers
  alias Hrafnsyn.Tracking

  @default_active_window_minutes 20
  @default_log_limit 50
  @default_history_hours 6

  def get_system_info(_request, _stream) do
    %Hrafnsyn.V1.SystemInfo{
      sources: CollectorConfig.list_sources() |> Enum.map(&Helpers.source_descriptor/1),
      counts: Tracking.active_counts() |> Helpers.active_counts(),
      web_url: HrafnsynWeb.Endpoint.url()
    }
  end

  def list_active_tracks(%Hrafnsyn.V1.ListActiveTracksRequest{} = req, _stream) do
    minutes = positive_or_default(req.active_window_minutes, @default_active_window_minutes)
    limit = positive_or_default(req.limit, 2_000)

    %Hrafnsyn.V1.ListActiveTracksResponse{
      tracks:
        Tracking.list_active_tracks(minutes: minutes, limit: limit)
        |> Enum.map(&Helpers.track_summary/1),
      counts: Tracking.active_counts(minutes) |> Helpers.active_counts()
    }
  end

  def search_tracks(%Hrafnsyn.V1.SearchTracksRequest{} = req, _stream) do
    minutes = positive_or_default(req.active_window_minutes, @default_active_window_minutes)
    limit = positive_or_default(req.limit, 8)

    %Hrafnsyn.V1.SearchTracksResponse{
      tracks:
        Tracking.search_active_tracks(req.query, minutes: minutes, limit: limit)
        |> Enum.map(&Helpers.track_summary/1)
    }
  end

  def get_track(%Hrafnsyn.V1.GetTrackRequest{} = req, _stream) do
    history_hours = positive_or_default(req.history_hours, @default_history_hours)
    log_limit = positive_or_default(req.log_limit, @default_log_limit)

    case resolve_track(req) do
      nil ->
        raise GRPC.RPCError, status: :not_found, message: "Track was not found"

      track ->
        %Hrafnsyn.V1.GetTrackResponse{
          track: Helpers.track_summary(track),
          route_points:
            track.id
            |> Tracking.recent_points(history_hours)
            |> Enum.map(&Helpers.track_point/1),
          route_stats:
            track.id
            |> Tracking.recent_route_stats(history_hours)
            |> Helpers.route_stats(),
          log_entries:
            track.id
            |> Tracking.recent_log_entries(log_limit)
            |> Enum.map(&Helpers.track_point/1)
        }
    end
  end

  defp resolve_track(%{track_id: id, identity: "", vehicle_type: :VEHICLE_TYPE_UNSPECIFIED})
       when id != "" do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Tracking.get_track(id)
      :error -> invalid_selector!()
    end
  end

  defp resolve_track(%{track_id: "", identity: identity, vehicle_type: vehicle})
       when vehicle in [:VEHICLE_TYPE_PLANE, :VEHICLE_TYPE_VESSEL] and
              byte_size(identity) in 1..256 do
    if not String.valid?(identity) or String.trim(identity) == "" or
         String.match?(identity, ~r/\p{Cc}/u) do
      invalid_selector!()
    end

    type = if vehicle == :VEHICLE_TYPE_PLANE, do: "plane", else: "vessel"
    Tracking.get_track_by_identity(type, identity)
  end

  defp resolve_track(_request), do: invalid_selector!()

  defp invalid_selector! do
    raise GRPC.RPCError,
      status: :invalid_argument,
      message: "Provide either a track ID or a vehicle type and identity"
  end

  def stream_track_updates(%Hrafnsyn.V1.StreamTrackUpdatesRequest{} = req, stream) do
    minutes = positive_or_default(req.active_window_minutes, @default_active_window_minutes)

    Stream.resource(
      fn ->
        Phoenix.PubSub.subscribe(Hrafnsyn.PubSub, Tracking.topic())
        minutes
      end,
      fn current_minutes ->
        receive do
          {:tracks_updated, track_ids} ->
            update = %Hrafnsyn.V1.TrackUpdate{
              track_ids: track_ids,
              counts: Tracking.active_counts(current_minutes) |> Helpers.active_counts(),
              sent_at: Helpers.timestamp(DateTime.utc_now(:second))
            }

            {[update], current_minutes}
        end
      end,
      fn _current_minutes -> :ok end
    )
    |> GRPC.Stream.from()
    |> GRPC.Stream.run_with(stream)
  end

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default
end
