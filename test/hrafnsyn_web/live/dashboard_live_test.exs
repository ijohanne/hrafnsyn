defmodule HrafnsynWeb.DashboardLiveTest do
  use HrafnsynWeb.ConnCase, async: false

  import Hrafnsyn.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.Ingest
  alias Hrafnsyn.Tracking

  setup do
    public_readonly? = Application.get_env(:hrafnsyn, :public_readonly?, true)

    on_exit(fn ->
      Application.put_env(:hrafnsyn, :public_readonly?, public_readonly?)
    end)

    :ok
  end

  test "redirects guests to the login page when public mode is disabled", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, false)

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/users/log-in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You must log in to access this page."
  end

  test "allows guests to reach the dashboard when public mode is enabled", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, true)

    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Unified Air and Sea Tracking"
  end

  test "auth-required dashboard deep links preserve the full shared target", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, false)

    path =
      "/?vehicle=plane&identity=406ABC&range=24&lat=36.15100&lon=-6.10100&zoom=10.40&bearing=18.00&pitch=32.00"

    conn = get(conn, path)

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == path
  end

  test "logged-in users get the durable profile menu shell", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, true)

    user = user_fixture()

    {:ok, _view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/")

    assert html =~ ~s(id="profile-menu")
    assert html =~ ~s(phx-hook="ProfileMenu")
    assert html =~ ~s(data-close-delay="180")
    assert html =~ ~s(href="/users/tokens")
  end

  test "legend renders plane and vessel toggles enabled by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "button.legend-toggle[data-track-toggle='plane'][aria-pressed='true']",
             "Aircraft"
           )

    assert has_element?(
             view,
             "button.legend-toggle[data-track-toggle='vessel'][aria-pressed='true']",
             "Vessels"
           )

    assert has_element?(view, ".legend-row-static", "Selected route")
  end

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

  test "selected aircraft render FlightAware photos and flight page links", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "406ABC", "AFR69ZJ", "F-GZNE", 36.101, -6.141)
             ])

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#track-grid .track-row")
    |> render_click()

    assert has_element?(
             view,
             "a.detail-action[href='https://www.flightaware.com/photos/aircraft/FGZNE']",
             "Photos"
           )

    assert has_element?(
             view,
             "a.detail-action[href='https://www.flightaware.com/live/modes/406abc/ident/AFR69ZJ/redirect']",
             "Flight page"
           )

    assert render(view) =~
             "External lookup. Opens in a new tab when this aircraft has enough identifiers."
  end

  test "deep links restore the selected track, range, and share metadata", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "406ABC", "AFR69ZJ", "F-GZNE", 36.101, -6.141)
             ])

    path =
      "/?vehicle=plane&identity=406ABC&range=24&lat=36.15100&lon=-6.10100&zoom=10.40&bearing=18.00&pitch=32.00"

    {:ok, view, html} = live(conn, path)

    assert html =~ "AFR69ZJ"
    assert has_element?(view, ".detail-hero p", "406ABC")
    assert has_element?(view, ".range-tab.is-active", "24h")

    assert has_element?(
             view,
             "#share-selected-track[data-share-vehicle='plane'][data-share-identity='406ABC'][data-share-range='24']",
             "Copy link"
           )
  end

  test "selected vessels render flag emoji and code in the detail card", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(vessel_source_fixture(), [
               vessel_observation(observed_at, "Ocean Venture", 36.101, -6.141)
             ])

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#track-grid .track-row")
    |> render_click()

    assert render(view) =~ "Flag"
    assert render(view) =~ "🇧🇸 BS"
  end

  test "selected aircraft render derived registration and flag details", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "A00001", nil, nil, 36.101, -6.141)
             ])

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#track-grid .track-row")
    |> render_click()

    assert render(view) =~ "Registration"
    assert render(view) =~ "N1"
    assert render(view) =~ "Flag"
    assert render(view) =~ "🇺🇸 US"
  end

  test "selected aircraft render enriched type and wake turbulence details", %{conn: conn} do
    observed_at = DateTime.utc_now(:second)

    assert {:ok, [_track_id]} =
             Ingest.ingest_batch(plane_source_fixture(), [
               plane_observation(observed_at, "406ABC", "AFR69ZJ", "F-GZNE", 36.101, -6.141, %{
                 aircraft_type: "A320",
                 type_description: "L2J",
                 wake_turbulence_category: "M"
               })
             ])

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#track-grid .track-row")
    |> render_click()

    assert render(view) =~ "ICAO type"
    assert render(view) =~ "A320"
    assert render(view) =~ "Type description"
    assert render(view) =~ "Landplane, 2 jet engines (L2J)"
    assert render(view) =~ "Wake turbulence"
    assert render(view) =~ "Medium (M)"
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

  defp plane_observation(
         observed_at,
         identity,
         callsign,
         registration,
         latitude,
         longitude,
         extra_attrs \\ %{}
       ) do
    Map.merge(
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
      },
      extra_attrs
    )
  end

  defp vessel_source_fixture do
    %Source{
      id: "ais-main",
      name: "AIS Main",
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
