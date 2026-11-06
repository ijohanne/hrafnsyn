defmodule Hrafnsyn.GRPC.TrackingServerTest do
  use Hrafnsyn.DataCase, async: true

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.GRPC.TrackingServer
  alias Hrafnsyn.Ingest
  alias Hrafnsyn.V1.GetTrackRequest

  test "advertises the configured canonical web URL" do
    assert TrackingServer.get_system_info(%Google.Protobuf.Empty{}, nil).web_url ==
             HrafnsynWeb.Endpoint.url()
  end

  test "resolves inactive exact identities without confusing aircraft and vessels" do
    vessel_id = ingest_track("vessel", "SHARED-IDENTITY")
    plane_id = ingest_track("plane", "SHARED-IDENTITY")

    request = %GetTrackRequest{
      vehicle_type: :VEHICLE_TYPE_VESSEL,
      identity: "SHARED-IDENTITY",
      history_hours: 6
    }

    # The additive fields must survive the same protobuf boundary as native clients.
    request = request |> GetTrackRequest.encode() |> GetTrackRequest.decode()
    response = TrackingServer.get_track(request, nil)
    assert response.track.id == vessel_id
    assert length(response.route_points) == 1

    response = TrackingServer.get_track(%{request | vehicle_type: :VEHICLE_TYPE_PLANE}, nil)
    assert response.track.id == plane_id
    assert Hrafnsyn.Tracking.list_active_tracks() == []
  end

  test "keeps existing ID requests compatible" do
    id = ingest_track("vessel", "LEGACY-ID")
    assert TrackingServer.get_track(%GetTrackRequest{track_id: id}, nil).track.id == id
  end

  test "reports missing identities without an active-list fallback" do
    error =
      assert_raise GRPC.RPCError, fn ->
        TrackingServer.get_track(
          %GetTrackRequest{vehicle_type: :VEHICLE_TYPE_VESSEL, identity: "missing"},
          nil
        )
      end

    assert error.status == GRPC.Status.not_found()
  end

  test "rejects ambiguous and malformed selectors before querying" do
    for request <- [
          %GetTrackRequest{},
          %GetTrackRequest{track_id: "not-a-uuid"},
          %GetTrackRequest{identity: "123"},
          %GetTrackRequest{vehicle_type: :VEHICLE_TYPE_PLANE},
          %GetTrackRequest{vehicle_type: :VEHICLE_TYPE_VESSEL, identity: "\n123"},
          %GetTrackRequest{vehicle_type: :VEHICLE_TYPE_VESSEL, identity: <<255>>},
          %GetTrackRequest{vehicle_type: :VEHICLE_TYPE_VESSEL, identity: "\u0085"},
          %GetTrackRequest{
            vehicle_type: :VEHICLE_TYPE_VESSEL,
            identity: String.duplicate("x", 257)
          },
          %GetTrackRequest{
            track_id: Ecto.UUID.generate(),
            vehicle_type: :VEHICLE_TYPE_PLANE,
            identity: "123"
          }
        ] do
      error = assert_raise GRPC.RPCError, fn -> TrackingServer.get_track(request, nil) end
      assert error.status == GRPC.Status.invalid_argument()
    end
  end

  defp ingest_track(vehicle, identity) do
    type = if vehicle == "plane", do: :plane, else: :vessel

    source = %Source{
      id: "share-#{vehicle}",
      name: "Share #{vehicle}",
      vehicle_type: type,
      adapter: if(type == :plane, do: :dump1090, else: :aistracker),
      base_url: "http://example.test"
    }

    observation = %{
      vehicle_type: vehicle,
      identity: identity,
      display_name: "Shared contact",
      latitude: 36.4152,
      longitude: -5.1568,
      observed_at: DateTime.add(DateTime.utc_now(:second), -7200, :second)
    }

    assert {:ok, [id]} = Ingest.ingest_batch(source, [observation])
    id
  end
end
