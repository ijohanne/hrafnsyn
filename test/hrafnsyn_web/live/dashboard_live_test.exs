defmodule HrafnsynWeb.DashboardLiveTest do
  use HrafnsynWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.Ingest
  alias Hrafnsyn.Tracking

  test "search stays collapsed by default and submitting an exact match selects the track", %{
    conn: conn
  } do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "406ABC", "AFR69ZJ", "F-GZNE", 36.101, -6.141)
             ])

    {:ok, view, html} = live(conn, ~p"/")

    refute html =~ "Press Enter to jump to an exact or unique active match."

    view
    |> element(".search-panel .panel-toggle")
    |> render_click()

    assert render(view) =~ "Press Enter to jump to an exact or unique active match."

    view
    |> form(".search-panel .search-form", search: %{query: "AFR69ZJ"})
    |> render_change()

    assert has_element?(view, "button.search-result-row", "AFR69ZJ")

    view
    |> form(".search-panel .search-form", search: %{query: "AFR69ZJ"})
    |> render_submit()

    assert has_element?(view, ".detail-card h2", "AFR69ZJ")
    assert has_element?(view, ".detail-hero p", "406ABC")
    refute render(view) =~ "Press Enter to jump to an exact or unique active match."
  end

  test "clicking a search result selects the requested track", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_first_track_id, _second_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "406ABC", "AFR69ZJ", "F-GZNE", 36.101, -6.141),
               plane_observation(observed_at, "406ABD", "AFR11AA", "F-HABC", 36.141, -6.181)
             ])

    [%{id: first_track_id}] = Tracking.search_active_tracks("AFR69ZJ")
    [%{id: second_track_id}] = Tracking.search_active_tracks("AFR11AA")

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element(".search-panel .panel-toggle")
    |> render_click()

    view
    |> form(".search-panel .search-form", search: %{query: "AFR"})
    |> render_change()

    assert has_element?(
             view,
             "button.search-result-row[phx-value-id='#{first_track_id}']",
             "AFR69ZJ"
           )

    assert has_element?(
             view,
             "button.search-result-row[phx-value-id='#{second_track_id}']",
             "AFR11AA"
           )

    view
    |> element("button.search-result-row[phx-value-id='#{second_track_id}']")
    |> render_click()

    assert has_element?(view, ".detail-card h2", "AFR11AA")
    assert has_element?(view, ".detail-hero p", "406ABD")
  end

  defp plane_source_fixture do
    %Source{
      id: "dump1090-main",
      name: "SkyAware Main",
      vehicle_type: :plane,
      adapter: :dump1090,
      base_url: "http://example.test"
    }
  end

  defp plane_observation(observed_at, identity, callsign, registration, latitude, longitude) do
    %{
      vehicle_type: "plane",
      identity: identity,
      display_name: callsign,
      callsign: callsign,
      registration: registration,
      destination: "AGP",
      latitude: latitude,
      longitude: longitude,
      speed: 387,
      heading: 236,
      altitude: 37_000,
      observed_at: observed_at,
      last_payload: %{"source" => "test"}
    }
  end
end
