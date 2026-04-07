defmodule Hrafnsyn.TrackingTest do
  use Hrafnsyn.DataCase, async: true

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.Ingest
  alias Hrafnsyn.Tracking

  describe "ingest pipeline" do
    test "merges identical vessels from multiple sources into one live track" do
      east_feed = source_fixture("ais-east", "AIS East")
      west_feed = source_fixture("ais-west", "AIS West")
      observed_at = DateTime.utc_now(:second)

      first = vessel_observation(observed_at, "MOROCCO EXPRESS 1", 36.1298, -5.3536)

      second =
        observed_at
        |> DateTime.add(10, :second)
        |> vessel_observation("MOROCCO EXPRESS 1", 36.1321, -5.3472)
        |> Map.put(:speed, 17)
        |> Map.put(:heading, 259)

      assert {:ok, [track_id]} = Ingest.ingest_batch(east_feed, [first])
      assert {:ok, [^track_id]} = Ingest.ingest_batch(west_feed, [second])

      [track] = Tracking.list_active_tracks(query: "express")
      assert track.id == track_id
      assert track.latest_source_id == west_feed.id
      assert track.latest_source_name == "AIS West"
      assert track.display_name == "MOROCCO EXPRESS 1"
      assert track.destination == "ALGECIRAS"

      route = Tracking.recent_points(track.id, 1)
      assert length(route) == 2
      assert Enum.map(route, & &1.source_id) == ["ais-east", "ais-west"]
      assert hd(route).latitude == 36.1298
      assert hd(route).longitude == -5.3536

      stats = Tracking.recent_route_stats(track.id, 1)
      assert stats.distance_meters > 0
      assert stats.observed_seconds == 10

      log_entries = Tracking.recent_log_entries(track.id)
      assert Enum.map(log_entries, & &1.source_name) == ["AIS West", "AIS East"]
    end

    test "search matches plane identifiers, callsigns, and registrations" do
      plane_feed = %Source{
        id: "dump1090-main",
        name: "SkyAware Main",
        vehicle_type: :plane,
        adapter: :dump1090,
        base_url: "http://example.test"
      }

      observed_at = DateTime.utc_now(:second)

      observation = %{
        vehicle_type: "plane",
        identity: "4CADE2",
        display_name: "RYR7FH",
        callsign: "RYR7FH",
        registration: "EI-DWH",
        destination: "AGP",
        latitude: 36.105,
        longitude: -6.148,
        speed: 387,
        heading: 236,
        altitude: 37_000,
        observed_at: observed_at,
        last_payload: %{"source" => "test"}
      }

      assert {:ok, [_track_id]} = Ingest.ingest_batch(plane_feed, [observation])

      assert [%{identity: "4CADE2"}] = Tracking.list_active_tracks(query: "4cade2")
      assert [%{identity: "4CADE2"}] = Tracking.list_active_tracks(query: "ryr7fh")
      assert [%{identity: "4CADE2"}] = Tracking.list_active_tracks(query: "ei-dwh")
    end

    test "resolve_active_track prefers exact matches and rejects ambiguous ones" do
      plane_feed = %Source{
        id: "dump1090-main",
        name: "SkyAware Main",
        vehicle_type: :plane,
        adapter: :dump1090,
        base_url: "http://example.test"
      }

      observed_at = DateTime.utc_now(:second)

      assert {:ok, [_first_track_id, _second_track_id]} =
               Ingest.ingest_batch(plane_feed, [
                 %{
                   vehicle_type: "plane",
                   identity: "406ABC",
                   display_name: "AFR69ZJ",
                   callsign: "AFR69ZJ",
                   registration: "F-GZNE",
                   destination: "CDG",
                   latitude: 36.101,
                   longitude: -6.141,
                   speed: 401,
                   heading: 28,
                   altitude: 36_000,
                   observed_at: observed_at,
                   last_payload: %{"source" => "test"}
                 },
                 %{
                   vehicle_type: "plane",
                   identity: "406ABD",
                   display_name: "AFR11AA",
                   callsign: "AFR11AA",
                   registration: "F-HABC",
                   destination: "ORY",
                   latitude: 36.141,
                   longitude: -6.181,
                   speed: 389,
                   heading: 45,
                   altitude: 35_500,
                   observed_at: observed_at,
                   last_payload: %{"source" => "test"}
                 }
               ])

      assert {:ok, %{identity: "406ABC"}} = Tracking.resolve_active_track("afr69zj")
      assert {:error, :ambiguous} = Tracking.resolve_active_track("afr")
      assert {:error, :not_found} = Tracking.resolve_active_track("unknown")
    end
  end

  defp source_fixture(id, name) do
    %Source{
      id: id,
      name: name,
      vehicle_type: :vessel,
      adapter: :ais_catcher,
      base_url: "http://example.test"
    }
  end

  defp vessel_observation(observed_at, name, latitude, longitude) do
    %{
      vehicle_type: "vessel",
      identity: "242080116",
      display_name: name,
      callsign: "C6FQ7",
      registration: "IMO 9262130",
      country: "Bahamas",
      status: "0",
      destination: "ALGECIRAS",
      latitude: latitude,
      longitude: longitude,
      speed: 16.4,
      heading: 261,
      observed_at: observed_at,
      last_payload: %{"name" => name}
    }
  end
end
