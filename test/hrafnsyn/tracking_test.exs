defmodule Hrafnsyn.TrackingTest do
  use Hrafnsyn.DataCase, async: true

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.Ingest
  alias Hrafnsyn.Tracking
  alias Hrafnsyn.Tracking.TrackPoint

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

    test "search matches plane identifiers, callsigns, registrations, and aircraft metadata" do
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
        aircraft_type: "B738",
        type_description: "Landplane, 2 jet engines (L2J)",
        wake_turbulence_category: "M",
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
      assert [%{identity: "4CADE2"}] = Tracking.list_active_tracks(query: "b738")
      assert [%{identity: "4CADE2"}] = Tracking.list_active_tracks(query: "landplane")
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

    test "prune_stale_points keeps one last-seen point per track before the cutoff" do
      source = source_fixture("ais-main", "AIS Main")
      now = DateTime.utc_now(:second)
      cutoff = DateTime.add(now, -7 * 24 * 60 * 60, :second)

      old_observed_at = DateTime.add(cutoff, -3_600, :second)
      last_seen_before_cutoff = DateTime.add(cutoff, -30, :second)
      recent_observed_at = DateTime.add(cutoff, 30, :second)

      assert {:ok, [track_id]} =
               Ingest.ingest_batch(source, [
                 vessel_observation(
                   DateTime.add(cutoff, -7_200, :second),
                   "OLD FERRY",
                   36.1,
                   -5.3
                 ),
                 vessel_observation(old_observed_at, "OLD FERRY", 36.2, -5.4),
                 vessel_observation(last_seen_before_cutoff, "OLD FERRY", 36.3, -5.5),
                 vessel_observation(recent_observed_at, "OLD FERRY", 36.4, -5.6)
               ])

      assert {:ok, 2} = Tracking.prune_stale_points(cutoff)

      points =
        TrackPoint
        |> where([point], point.track_id == ^track_id)
        |> order_by([point], asc: point.observed_at)
        |> Repo.all()

      assert Enum.map(points, & &1.observed_at) == [
               last_seen_before_cutoff,
               recent_observed_at
             ]

      assert [%{latitude: 36.3, longitude: -5.5}, %{latitude: 36.4, longitude: -5.6}] =
               Tracking.recent_points(track_id, 24 * 8)
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
