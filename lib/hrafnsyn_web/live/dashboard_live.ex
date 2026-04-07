defmodule HrafnsynWeb.DashboardLive do
  use HrafnsynWeb, :live_view

  alias Hrafnsyn.Collectors.Config, as: CollectorConfig
  alias Hrafnsyn.Tracking

  @ranges [{"1h", 1}, {"6h", 6}, {"24h", 24}, {"72h", 72}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Hrafnsyn.PubSub, Tracking.topic())

    socket =
      socket
      |> assign(:page_title, "Unified Air and Sea Tracking")
      |> assign(:map_style_url, Application.get_env(:hrafnsyn, :map_style_url))
      |> assign(:public_readonly?, Application.get_env(:hrafnsyn, :public_readonly?, true))
      |> assign(:source_cards, source_cards())
      |> assign(:ranges, @ranges)
      |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
      |> assign(:search_query, "")
      |> assign(:range_hours, 6)
      |> assign(:tracks, Tracking.list_active_tracks())
      |> assign(:selected_track, nil)
      |> assign(:route_points, [])
      |> assign(:log_entries, [])
      |> sync_counts()

    if connected?(socket), do: send(self(), :sync_map)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))
      |> assign(:tracks, Tracking.list_active_tracks(query: query))
      |> sync_counts()

    send(self(), :sync_map)
    {:noreply, socket}
  end

  def handle_event("select_track", %{"id" => id}, socket) do
    {:noreply, select_track(socket, id)}
  end

  def handle_event("set_range", %{"hours" => hours}, socket) do
    range_hours = String.to_integer(hours)

    socket =
      socket
      |> assign(:range_hours, range_hours)
      |> maybe_reload_selected()

    send(self(), :sync_map)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tracks_updated, _track_ids}, socket) do
    socket =
      socket
      |> assign(:tracks, Tracking.list_active_tracks(query: socket.assigns.search_query))
      |> maybe_reload_selected()
      |> sync_counts()

    send(self(), :sync_map)
    {:noreply, socket}
  end

  def handle_info(:sync_map, socket) do
    {:noreply, push_map_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="shell-grid">
        <div class="map-column">
          <div class="map-header">
            <div>
              <p class="eyebrow">Hrafnsyn</p>
              <h1>Air and sea traffic on one living map.</h1>
              <p class="lede">
                Plane ADS-B and AIS vessel feeds are merged into a single realtime view, with searchable identities,
                replayable tracks, and a durable log in Postgres.
              </p>
            </div>
            <div class="stats-strip">
              <article>
                <span>Total visible</span>
                <strong>{@track_count}</strong>
              </article>
              <article>
                <span>Aircraft</span>
                <strong>{@plane_count}</strong>
              </article>
              <article>
                <span>Vessels</span>
                <strong>{@vessel_count}</strong>
              </article>
            </div>
          </div>

          <div class="tracking-map-frame">
            <div
              id="tracking-map"
              class="tracking-map"
              phx-hook="TrackingMap"
              data-style-url={@map_style_url}
              data-glyph-color={Application.get_env(:hrafnsyn, :map_glyph_color)}
            >
            </div>

            <div class="map-overlay top-left">
              <span class="overlay-label">Merged LiveView map</span>
              <strong>{length(@source_cards)} active upstream feeds</strong>
              <small>
                Each feed runs in its own collector process and merges by tracked identity.
              </small>
            </div>

            <div class="map-overlay bottom-left legend-card">
              <div class="legend-row">
                <span class="legend-swatch plane"></span>
                <span>Aircraft</span>
              </div>
              <div class="legend-row">
                <span class="legend-swatch vessel"></span>
                <span>Vessels</span>
              </div>
              <div class="legend-row">
                <span class="legend-swatch route"></span>
                <span>Selected route</span>
              </div>
            </div>
          </div>
        </div>

        <aside class="side-column">
          <section class="panel filter-panel">
            <div class="panel-title">
              <span>Search</span>
              <span class="subtle">Boat / plane id, callsign, name</span>
            </div>
            <.form for={@search_form} phx-change="search" class="search-form">
              <.input field={@search_form[:query]} type="text" placeholder="Search tracks..." />
            </.form>
            <p :if={@public_readonly? and is_nil(@current_scope)} class="readonly-note">
              Public access is readonly. Add an admin user later to unlock account management.
            </p>

            <div class="feed-grid">
              <article :for={source <- @source_cards} class="source-card">
                <div class="source-card-top">
                  <span class={["track-pill", source.vehicle_type]}>
                    {String.upcase(source.vehicle_type)}
                  </span>
                  <span class="source-meta">{source.adapter}</span>
                </div>
                <strong>{source.name}</strong>
                <small>{source.poll_label}</small>
              </article>
            </div>
          </section>

          <section class="panel track-list-panel">
            <div class="panel-title">
              <span>Live Contacts</span>
              <span class="subtle">{@track_count} active</span>
            </div>
            <div class="track-list">
              <button
                :for={track <- @tracks}
                type="button"
                class={["track-row", @selected_track && @selected_track.id == track.id && "is-active"]}
                phx-click="select_track"
                phx-value-id={track.id}
              >
                <span class={["track-pill", track.vehicle_type]}>
                  {String.upcase(track.vehicle_type)}
                </span>
                <div class="track-copy">
                  <strong>{track.display_name || track.identity}</strong>
                  <span>{track.identity}</span>
                </div>
                <div class="track-metrics">
                  <span>{format_speed(track.speed)}</span>
                  <span>{format_age(track.observed_at)}</span>
                </div>
              </button>

              <div :if={Enum.empty?(@tracks)} class="list-empty">
                No active tracks match the current filter.
              </div>
            </div>
          </section>

          <section class="panel detail-panel">
            <div class="panel-title">
              <span>Detail</span>
              <div :if={@selected_track} class="range-tabs">
                <button
                  :for={{label, hours} <- @ranges}
                  type="button"
                  class={["range-tab", @range_hours == hours && "is-active"]}
                  phx-click="set_range"
                  phx-value-hours={hours}
                >
                  {label}
                </button>
              </div>
            </div>

            <div :if={@selected_track} class="detail-card">
              <div class="detail-hero">
                <span class={["track-pill", @selected_track.vehicle_type]}>
                  {String.upcase(@selected_track.vehicle_type)}
                </span>
                <div>
                  <h2>{@selected_track.display_name || @selected_track.identity}</h2>
                  <p>{@selected_track.identity}</p>
                </div>
              </div>

              <dl class="detail-grid">
                <div :for={
                  {label, value} <- detail_items(@selected_track, @route_points, @log_entries)
                }>
                  <dt>{label}</dt>
                  <dd>{value}</dd>
                </div>
              </dl>

              <div class="log-header">
                <strong>Recent log</strong>
                <span>{length(@log_entries)} rows</span>
              </div>

              <div class="log-list">
                <article :for={entry <- @log_entries} class="log-row">
                  <div>
                    <strong>{format_timestamp(entry.observed_at)}</strong>
                    <span>{entry.source_name}</span>
                  </div>
                  <div>
                    <span>{format_latlon(entry.latitude, entry.longitude)}</span>
                    <span>{format_speed(entry.speed)} • {format_heading(entry.heading)}</span>
                  </div>
                </article>
              </div>
            </div>

            <div :if={is_nil(@selected_track)} class="empty-state">
              Select a plane or vessel from the map or the live list to inspect its route and recent history.
            </div>
          </section>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  defp select_track(socket, id) do
    case Tracking.get_track(id) do
      nil ->
        socket

      track ->
        socket =
          socket
          |> assign(:selected_track, track)
          |> assign(:route_points, Tracking.recent_points(track.id, socket.assigns.range_hours))
          |> assign(:log_entries, Tracking.recent_log_entries(track.id))

        send(self(), :sync_map)
        socket
    end
  end

  defp maybe_reload_selected(%{assigns: %{selected_track: nil}} = socket), do: socket
  defp maybe_reload_selected(socket), do: select_track(socket, socket.assigns.selected_track.id)

  defp push_map_state(socket) do
    push_event(socket, "map:sync", %{
      selected_track_id: socket.assigns.selected_track && socket.assigns.selected_track.id,
      tracks: Enum.map(socket.assigns.tracks, &serialize_track/1),
      route: Enum.map(socket.assigns.route_points, &serialize_point/1)
    })
  end

  defp serialize_track(track) do
    %{
      id: track.id,
      identity: track.identity,
      display_name: track.display_name || track.identity,
      vehicle_type: track.vehicle_type,
      latitude: track.latitude,
      longitude: track.longitude,
      speed: track.speed,
      heading: track.heading,
      altitude: track.altitude,
      observed_at: DateTime.to_iso8601(track.observed_at)
    }
  end

  defp serialize_point(point) do
    %{
      id: point.id,
      latitude: point.latitude,
      longitude: point.longitude,
      observed_at: DateTime.to_iso8601(point.observed_at)
    }
  end

  defp sync_counts(socket) do
    counts =
      Enum.reduce(socket.assigns.tracks, %{plane: 0, vessel: 0}, fn track, acc ->
        case track.vehicle_type do
          "plane" -> Map.update!(acc, :plane, &(&1 + 1))
          "vessel" -> Map.update!(acc, :vessel, &(&1 + 1))
          _other -> acc
        end
      end)

    socket
    |> assign(:track_count, length(socket.assigns.tracks))
    |> assign(:plane_count, counts.plane)
    |> assign(:vessel_count, counts.vessel)
  end

  defp source_cards do
    Enum.map(CollectorConfig.list_sources(), fn source ->
      %{
        id: source.id,
        name: source.name,
        vehicle_type: Atom.to_string(source.vehicle_type),
        adapter: source.adapter |> Atom.to_string() |> String.replace("_", "-"),
        poll_label:
          "poll every #{source.poll_interval_ms |> div(100) |> Kernel./(10) |> :erlang.float_to_binary(decimals: 1)}s"
      }
    end)
  end

  defp detail_items(track, route_points, log_entries) do
    common = [
      {"Source", track.latest_source_name || "-"},
      {"Observed", format_timestamp(track.observed_at)},
      {"Speed", format_speed(track.speed)},
      {"Heading", format_heading(track.heading)},
      {"Destination", track.destination || "-"},
      {"Route points", Integer.to_string(length(route_points))},
      {"Logged rows", Integer.to_string(length(log_entries))}
    ]

    case track.vehicle_type do
      "plane" -> common ++ plane_detail_items(track)
      "vessel" -> common ++ vessel_detail_items(track)
      _other -> common
    end
  end

  defp plane_detail_items(track) do
    [
      {"Altitude", format_altitude(track.altitude)},
      {"Callsign", track.callsign || "-"},
      {"Registration", track.registration || "-"},
      {"Category", track.category || "-"}
    ]
  end

  defp vessel_detail_items(track) do
    [
      {"IMO", track.registration || "-"},
      {"Callsign", track.callsign || "-"},
      {"Flag", track.country || "-"},
      {"Status", track.status || "-"}
    ]
  end

  defp format_speed(nil), do: "-"
  defp format_speed(speed), do: "#{round_number(speed, 1)} kt"
  defp format_heading(nil), do: "-"
  defp format_heading(heading), do: "#{heading |> round_number(0) |> trunc()}°"
  defp format_altitude(nil), do: "-"
  defp format_altitude(0), do: "surface"
  defp format_altitude(altitude), do: "#{altitude} ft"
  defp format_age(nil), do: "-"

  defp format_age(observed_at),
    do: "#{DateTime.diff(DateTime.utc_now(:second), observed_at, :second)}s"

  defp format_timestamp(nil), do: "-"
  defp format_timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  defp format_latlon(nil, nil), do: "-"
  defp format_latlon(lat, lon), do: "#{round_number(lat, 4)}, #{round_number(lon, 4)}"

  defp round_number(number, precision) when is_integer(number),
    do: Float.round(number / 1, precision)

  defp round_number(number, precision) when is_float(number), do: Float.round(number, precision)
end
