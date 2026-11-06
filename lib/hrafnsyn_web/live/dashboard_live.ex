defmodule HrafnsynWeb.DashboardLive do
  use HrafnsynWeb, :live_view

  alias Hrafnsyn.Aircraft.TypeDescription
  alias Hrafnsyn.Collectors.Config, as: CollectorConfig
  alias Hrafnsyn.CountryFlags
  alias Hrafnsyn.Tracking
  alias Hrafnsyn.Tracking.ExternalLinks

  @ranges [{"1h", 1}, {"6h", 6}, {"24h", 24}, {"72h", 72}]
  @default_range_hours 6
  @range_hours Enum.map(@ranges, &elem(&1, 1))

  @impl true
  def mount(params, _session, socket) do
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
      |> assign(:search_open, false)
      |> assign(:search_results, [])
      |> assign(:search_feedback, nil)
      |> assign(:range_hours, @default_range_hours)
      |> assign(:shared_map_view, nil)
      |> assign(:tracks, Tracking.list_active_tracks())
      |> assign(:selected_track, nil)
      |> assign(:route_points, [])
      |> assign(:route_stats, %{distance_meters: 0.0, observed_seconds: 0})
      |> assign(:log_entries, [])
      |> sync_counts()
      |> restore_shared_context(params)

    if connected?(socket), do: send(self(), :sync_map)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))
      |> assign(:search_results, Tracking.search_active_tracks(query, limit: 8))
      |> assign(:search_feedback, nil)
      |> maybe_open_search(query)

    {:noreply, socket}
  end

  def handle_event("submit_search", %{"search" => %{"query" => query}}, socket) do
    case Tracking.resolve_active_track(query, limit: 8) do
      {:ok, track} ->
        {:noreply, socket |> select_track(track.id) |> clear_search()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:search_feedback, search_feedback_message(reason))
         |> assign(:search_open, true)}
    end
  end

  def handle_event("select_search_result", %{"id" => id}, socket) do
    {:noreply, socket |> select_track(id) |> clear_search()}
  end

  def handle_event("toggle_search", _params, socket) do
    {:noreply, assign(socket, :search_open, !socket.assigns.search_open)}
  end

  def handle_event("open_search", _params, socket) do
    {:noreply, assign(socket, :search_open, true)}
  end

  def handle_event("close_search", _params, socket) do
    {:noreply, clear_search(socket)}
  end

  def handle_event("select_track", %{"id" => id}, socket) do
    {:noreply, select_track(socket, id)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, socket |> clear_selection() |> push_map_state()}
  end

  def handle_event("overview_map", _params, socket) do
    {:noreply,
     socket
     |> clear_selection()
     |> push_map_state()
     |> push_event("map:overview", %{})}
  end

  def handle_event("share_link_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Share link copied to your clipboard.")}
  end

  def handle_event("share_link_ready", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       "Clipboard access was blocked. Copy the share link from the dialog."
     )}
  end

  def handle_event("share_link_failed", _params, socket) do
    {:noreply, put_flash(socket, :error, "Couldn't prepare a share link right now.")}
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
      |> assign(:tracks, Tracking.list_active_tracks())
      |> refresh_search_results()
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
      <section
        class={["tracking-workspace", @selected_track && "has-selection"]}
        aria-label="Live tracking workspace"
      >
        <div class="workspace-toolbar">
          <h1>Live traffic</h1>
          <div class="traffic-counts" aria-label="Active contacts">
            <span><span class="type-dot plane"></span><strong>{@plane_count}</strong> aircraft</span>
            <span><span class="type-dot vessel"></span><strong>{@vessel_count}</strong> vessels</span>
          </div>
          <section class="search-panel" aria-label="Find a contact">
            <.form
              for={@search_form}
              id="traffic-search"
              phx-change="search"
              phx-submit="submit_search"
              class="search-form"
            >
              <.icon name="hero-magnifying-glass" class="search-icon size-4" />
              <input
                type="search"
                id="search_query"
                name="search[query]"
                value={@search_query}
                placeholder="Search callsign, name or identity"
                aria-label="Search contacts"
                autocomplete="off"
                phx-debounce="200"
                phx-focus="open_search"
              />
              <button
                :if={@search_query != ""}
                type="button"
                class="search-clear"
                phx-click="close_search"
                aria-label="Clear search"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </.form>
            <p id="search-status" class="sr-only" role="status" aria-live="polite" aria-atomic="true">
              <%= cond do %>
                <% @search_feedback -> %>
                  {@search_feedback}
                <% @search_query != "" and @search_results == [] -> %>
                  No active contacts match. Try a callsign or identity.
                <% @search_query != "" -> %>
                  {length(@search_results)} matching contacts.
                <% true -> %>
              <% end %>
            </p>
            <div
              :if={@search_query != "" or @search_feedback}
              class="search-results"
              id="search-results"
            >
              <p :if={@search_feedback} class="search-feedback">{@search_feedback}</p>
              <button
                :for={track <- @search_results}
                type="button"
                class="track-row search-result-row"
                phx-click="select_search_result"
                phx-value-id={track.id}
              >
                <.icon
                  name={
                    if track.vehicle_type == "plane", do: "hero-paper-airplane", else: "hero-lifebuoy"
                  }
                  class={["contact-icon size-5", track.vehicle_type]}
                />
                <span class="track-copy"><strong>{track.display_name || track.identity}</strong><span>{track.identity}</span></span>
                <span class="track-metrics"><span>{format_speed(track.speed)}</span><span>{format_age(
                  track.observed_at
                )}</span></span>
              </button>
              <p :if={@search_results == [] and is_nil(@search_feedback)} class="list-empty">
                No active contacts match. Try a callsign or identity.
              </p>
              <p :if={@search_results != []} class="search-hint">
                Choose a contact, or press Enter for an exact match.
              </p>
            </div>
          </section>
        </div>

        <div class="workspace-body">
          <div
            id="tracking-map-frame"
            class="tracking-map-frame"
            phx-hook="TrackingMap"
            data-style-url={@map_style_url}
            data-glyph-color={Application.get_env(:hrafnsyn, :map_glyph_color)}
          >
            <div id="tracking-map" class="tracking-map" phx-update="ignore" data-map-canvas></div>
            <button type="button" class="map-overview" phx-click="overview_map">
              <.icon name="hero-arrows-pointing-out" class="size-4" /> Overview
            </button>
            <div
              class="map-overlay bottom-left legend-card"
              aria-label="Map legend and visibility controls"
            >
              <button
                type="button"
                class="legend-row legend-toggle is-active"
                data-track-toggle="plane"
                aria-pressed="true"
              >
                <span class="legend-swatch plane"></span><span>Aircraft</span>
              </button>
              <button
                type="button"
                class="legend-row legend-toggle is-active"
                data-track-toggle="vessel"
                aria-pressed="true"
              >
                <span class="legend-swatch vessel"></span><span>Vessels</span>
              </button>
              <div class="legend-row legend-row-static">
                <span class="legend-swatch route"></span><span>Selected route</span>
              </div>
            </div>
          </div>

          <aside class="traffic-inspector" aria-label="Contacts and track details">
            <section :if={@selected_track} class="detail-panel">
              <div class="inspector-heading">
                <h2>Track details</h2>
                <button
                  type="button"
                  class="inspector-close"
                  phx-click="clear_selection"
                  aria-label="Close track details"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
              <div class="detail-card" id="selected-track-detail" data-preserve-scroll>
                <% external_actions = detail_external_actions(@selected_track) %>
                <div class="detail-hero">
                  <div>
                    <h2>{@selected_track.display_name || @selected_track.identity}</h2><p>
                      {@selected_track.identity}
                      <span class={["track-pill", @selected_track.vehicle_type]}>
                        · {if @selected_track.vehicle_type == "plane", do: "Aircraft", else: "Vessel"}
                      </span>
                    </p>
                  </div>
                </div>
                <p class="observation-age">Last observed {format_age(@selected_track.observed_at)}</p>
                <dl class="movement-metrics">
                  <div>
                    <dt>Speed</dt><dd>{format_speed(@selected_track.speed)}</dd>
                  </div>
                  <div>
                    <dt>Heading</dt><dd>{format_heading(@selected_track.heading)}</dd>
                  </div>
                  <div :if={@selected_track.vehicle_type == "plane"}>
                    <dt>Altitude</dt><dd>{format_altitude(@selected_track.altitude)}</dd>
                  </div>
                  <div :if={@selected_track.vehicle_type == "vessel" and @selected_track.destination}>
                    <dt>Destination</dt><dd>{@selected_track.destination}</dd>
                  </div>
                </dl>
                <div class="route-heading">
                  <h3>Route history</h3><div class="range-tabs" aria-label="Route history duration">
                    <button
                      :for={{label, hours} <- @ranges}
                      type="button"
                      class={["range-tab", @range_hours == hours && "is-active"]}
                      phx-click="set_range"
                      phx-value-hours={hours}
                      aria-pressed={if @range_hours == hours, do: "true", else: "false"}
                    >{label}</button>
                  </div>
                </div>
                <p class="route-summary">
                  {format_distance(@route_stats.distance_meters)} over {format_duration(
                    @route_stats.observed_seconds
                  )}
                </p>
                <details id="track-identification" class="track-identification" data-preserve-open>
                  <summary>Identification &amp; source</summary>
                  <dl class="detail-grid">
                    <div :for={
                      {label, value} <-
                        detail_items(@selected_track, @route_points, @route_stats, @log_entries)
                    }>
                      <dt>{label}</dt><dd>{value}</dd>
                    </div>
                  </dl>
                </details>
                <div class="detail-actions-row">
                  <button
                    id="share-selected-track"
                    type="button"
                    class="detail-action"
                    phx-hook="ShareSelection"
                    data-share-vehicle={@selected_track.vehicle_type}
                    data-share-identity={@selected_track.identity}
                    data-share-range={@range_hours}
                  >
                    <.icon name="hero-link" class="size-4" /> Copy link
                  </button>
                  <a
                    id="open-selected-track-in-app"
                    class="detail-action"
                    href={
                      Hrafnsyn.MobileLinks.open_url(
                        @selected_track.vehicle_type,
                        @selected_track.identity,
                        @range_hours
                      )
                    }
                  >
                    <.icon name="hero-device-phone-mobile" class="size-4" /> Open in app
                  </a>
                  <a
                    :for={action <- external_actions}
                    class="detail-action"
                    href={action.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    title={action.description}
                  >{action.label}</a>
                </div>
                <div class="log-header">
                  <h3>Recent observations</h3><span>{length(@log_entries)}</span>
                </div>
                <div id="detail-log-list" class="log-list" data-preserve-scroll>
                  <article :for={entry <- @log_entries} id={"log-#{entry.id}"} class="log-row">
                    <div>
                      <strong>{format_timestamp(entry.observed_at)}</strong><span>{entry.source_name}</span>
                    </div>
                    <div>
                      <span>{format_latlon(entry.latitude, entry.longitude)}</span><span>{format_speed(
                        entry.speed
                      )} · {format_heading(entry.heading)}</span>
                    </div>
                  </article>
                  <p :if={@log_entries == []} class="list-empty">
                    No observations in this interval. Try a longer range.
                  </p>
                </div>
              </div>
            </section>

            <section
              :if={is_nil(@selected_track)}
              class="live-contacts-panel"
              id="live-contacts-panel"
            >
              <div class="inspector-heading">
                <h2>Live contacts</h2><span class="subtle">{@track_count} active</span>
              </div>
              <div class="contact-columns" aria-hidden="true">
                <span>Contact / identity</span><span>Speed / last seen</span>
              </div>
              <div id="track-grid" class="track-grid" data-preserve-scroll>
                <button
                  :for={track <- @tracks}
                  id={"track-#{track.id}"}
                  type="button"
                  class="track-row"
                  phx-click="select_track"
                  phx-value-id={track.id}
                >
                  <.icon
                    name={
                      if track.vehicle_type == "plane",
                        do: "hero-paper-airplane",
                        else: "hero-lifebuoy"
                    }
                    class={["contact-icon size-5", track.vehicle_type]}
                  />
                  <span class="track-copy"><strong>{track.display_name || track.identity}</strong><span>{track.identity}</span></span>
                  <span class="track-metrics"><span>{format_speed(track.speed)}</span><span>{format_age(
                    track.observed_at
                  )}</span></span>
                </button>
                <div :if={@tracks == []} class="list-empty">
                  <h3>No active contacts</h3><p>
                    New observations will appear here automatically. You can still explore the map.
                  </p>
                </div>
              </div>
            </section>
            <details id="traffic-sources" class="source-panel" data-preserve-open>
              <summary>
                {length(@source_cards)} configured sources
                <span :if={@public_readonly? and is_nil(@current_scope)}>Read only</span>
              </summary>
              <div class="feed-grid">
                <article :for={source <- @source_cards} class="source-card">
                  <strong>{source.name}</strong><small>{source.poll_label}</small>
                </article>
              </div>
            </details>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp select_track(socket, id) do
    select_track(socket, id, [])
  end

  defp select_track(socket, id, opts) do
    case Tracking.get_track(id) do
      nil ->
        socket

      track ->
        socket
        |> load_selected_track(track)
        |> maybe_sync_map(opts)
    end
  end

  defp clear_search(socket) do
    socket
    |> assign(:search_query, "")
    |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
    |> assign(:search_open, false)
    |> assign(:search_results, [])
    |> assign(:search_feedback, nil)
  end

  defp clear_selection(socket) do
    socket
    |> assign(:selected_track, nil)
    |> assign(:route_points, [])
    |> assign(:route_stats, %{distance_meters: 0.0, observed_seconds: 0})
    |> assign(:log_entries, [])
    |> assign(:shared_map_view, nil)
  end

  defp maybe_open_search(socket, query) do
    if String.trim(query) == "" do
      socket
    else
      assign(socket, :search_open, true)
    end
  end

  defp refresh_search_results(socket) do
    assign(
      socket,
      :search_results,
      Tracking.search_active_tracks(socket.assigns.search_query, limit: 8)
    )
  end

  defp search_feedback_message(:blank_query),
    do: "Enter a callsign, identifier, or name to search."

  defp search_feedback_message(:not_found), do: "No active track matches that query right now."

  defp search_feedback_message(:ambiguous),
    do: "More than one active track matches. Pick one from the results below."

  defp maybe_reload_selected(%{assigns: %{selected_track: nil}} = socket), do: socket
  defp maybe_reload_selected(socket), do: select_track(socket, socket.assigns.selected_track.id)

  defp push_map_state(socket) do
    push_event(socket, "map:sync", %{
      selected_track_id: socket.assigns.selected_track && socket.assigns.selected_track.id,
      tracks: Enum.map(socket.assigns.tracks, &serialize_track/1),
      route: Enum.map(socket.assigns.route_points, &serialize_point/1),
      shared_view: socket.assigns.shared_map_view
    })
  end

  defp restore_shared_context(socket, params) do
    socket =
      socket
      |> assign(:range_hours, parse_range_hours(params["range"]))
      |> assign(:shared_map_view, parse_shared_map_view(params))

    case shared_track_selector(params) do
      nil ->
        socket

      {vehicle_type, identity} ->
        case Tracking.get_track_by_identity(vehicle_type, identity) do
          nil ->
            put_flash(socket, :error, "The shared track is no longer available.")

          track ->
            select_track(socket, track.id, sync?: false)
        end
    end
  end

  defp load_selected_track(socket, track) do
    socket
    |> assign(:selected_track, track)
    |> assign(:route_points, Tracking.recent_points(track.id, socket.assigns.range_hours))
    |> assign(
      :route_stats,
      Tracking.recent_route_stats(track.id, socket.assigns.range_hours)
    )
    |> assign(:log_entries, Tracking.recent_log_entries(track.id))
  end

  defp maybe_sync_map(socket, opts) do
    if Keyword.get(opts, :sync?, true), do: send(self(), :sync_map)
    socket
  end

  defp shared_track_selector(%{"vehicle" => vehicle_type, "identity" => identity})
       when vehicle_type in ["plane", "vessel"] and is_binary(identity) and identity != "" do
    {vehicle_type, identity}
  end

  defp shared_track_selector(_params), do: nil

  defp parse_range_hours(nil), do: @default_range_hours

  defp parse_range_hours(value) do
    case Integer.parse(value) do
      {hours, ""} when hours in @range_hours -> hours
      _other -> @default_range_hours
    end
  end

  defp parse_shared_map_view(params) do
    with {:ok, latitude} <- parse_bounded_float(params["lat"], -90.0, 90.0),
         {:ok, longitude} <- parse_bounded_float(params["lon"], -180.0, 180.0),
         {:ok, zoom} <- parse_bounded_float(params["zoom"], 0.0, 22.0),
         {:ok, bearing} <- parse_optional_bounded_float(params["bearing"], -360.0, 360.0, 0.0),
         {:ok, pitch} <- parse_optional_bounded_float(params["pitch"], 0.0, 85.0, 0.0) do
      %{
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
        key:
          Enum.join(
            [
              format_share_float(latitude, 5),
              format_share_float(longitude, 5),
              format_share_float(zoom, 2),
              format_share_float(bearing, 2),
              format_share_float(pitch, 2)
            ],
            ":"
          )
      }
    else
      _error -> nil
    end
  end

  defp parse_bounded_float(nil, _min, _max), do: :error

  defp parse_bounded_float(value, min, max) do
    case Float.parse(value) do
      {number, ""} when number >= min and number <= max -> {:ok, number}
      _other -> :error
    end
  end

  defp parse_optional_bounded_float(nil, _min, _max, default), do: {:ok, default}
  defp parse_optional_bounded_float("", _min, _max, default), do: {:ok, default}

  defp parse_optional_bounded_float(value, min, max, _default),
    do: parse_bounded_float(value, min, max)

  defp format_share_float(number, decimals) do
    :erlang.float_to_binary(number, decimals: decimals)
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
      callsign: track.callsign,
      registration: track.registration,
      aircraft_type: track.aircraft_type,
      type_description: format_type_description(track.type_description),
      wake_turbulence_category: track.wake_turbulence_category,
      destination: track.destination,
      country: track.country,
      country_display: CountryFlags.format(track.country),
      status: track.status,
      source_name: track.latest_source_name,
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

  defp detail_items(track, route_points, route_stats, log_entries) do
    common = [
      {"Source", track.latest_source_name || "-"},
      {"Observed", format_timestamp(track.observed_at)},
      {"Speed", format_speed(track.speed)},
      {"Heading", format_heading(track.heading)},
      {"Destination", track.destination || "-"},
      {"Tracked distance", format_distance(route_stats.distance_meters)},
      {"Observed span", format_duration(route_stats.observed_seconds)},
      {"Route points", Integer.to_string(length(route_points))},
      {"Logged rows", Integer.to_string(length(log_entries))}
    ]

    case track.vehicle_type do
      "plane" -> common ++ detail_country_items(track) ++ plane_detail_items(track)
      "vessel" -> common ++ detail_country_items(track) ++ vessel_detail_items(track)
      _other -> common
    end
  end

  defp detail_external_actions(track), do: ExternalLinks.aircraft_actions(track)

  defp plane_detail_items(track) do
    [
      {"Altitude", format_altitude(track.altitude)},
      {"Callsign", track.callsign || "-"},
      {"Registration", track.registration || "-"},
      {"ICAO type", track.aircraft_type || "-"},
      {"Type description", format_type_description(track.type_description)},
      {"Wake turbulence", format_wake_turbulence(track.wake_turbulence_category)},
      {"Category", track.category || "-"}
    ]
  end

  defp vessel_detail_items(track) do
    [
      {"IMO", track.registration || "-"},
      {"Callsign", track.callsign || "-"},
      {"Status", track.status || "-"}
    ]
  end

  defp detail_country_items(track) do
    case CountryFlags.format(track.country) do
      nil when track.vehicle_type == "vessel" -> [{"Flag", "-"}]
      nil -> []
      country_display -> [{"Flag", country_display}]
    end
  end

  defp format_speed(nil), do: "-"
  defp format_speed(speed), do: "#{round_number(speed, 1)} kt"
  defp format_heading(nil), do: "-"
  defp format_heading(heading), do: "#{heading |> round_number(0) |> trunc()}°"
  defp format_altitude(nil), do: "-"
  defp format_altitude(0), do: "surface"
  defp format_altitude(altitude), do: "#{altitude} ft"
  defp format_type_description(nil), do: "-"

  defp format_type_description(value) do
    expanded = TypeDescription.expand(value) || value

    case Regex.run(~r/^(.*)\(([A-Z0-9]+)\)$/, expanded) do
      [_, description, code] ->
        description =
          description
          |> String.trim()
          |> String.downcase()
          |> String.split(", ", trim: true)
          |> Enum.map_join(", ", &String.capitalize/1)

        "#{description} (#{code})"

      _other ->
        expanded
    end
  end

  defp format_wake_turbulence(nil), do: "-"
  defp format_wake_turbulence("H"), do: "Heavy (H)"
  defp format_wake_turbulence("J"), do: "Super (J)"
  defp format_wake_turbulence("L"), do: "Light (L)"
  defp format_wake_turbulence("M"), do: "Medium (M)"
  defp format_wake_turbulence(value), do: value
  defp format_age(nil), do: "-"

  defp format_age(observed_at),
    do: "#{DateTime.diff(DateTime.utc_now(:second), observed_at, :second)}s"

  defp format_timestamp(nil), do: "-"
  defp format_timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  defp format_latlon(nil, nil), do: "-"
  defp format_latlon(lat, lon), do: "#{round_number(lat, 4)}, #{round_number(lon, 4)}"
  defp format_distance(nil), do: "-"

  defp format_distance(distance_meters) when distance_meters < 1_000 do
    "#{round_number(distance_meters, 0) |> trunc()} m"
  end

  defp format_distance(distance_meters) do
    "#{round_number(distance_meters / 1_000, 1)} km"
  end

  defp format_duration(nil), do: "-"
  defp format_duration(0), do: "0s"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3_600 do
    minutes = div(seconds, 60)
    remainder = rem(seconds, 60)
    if remainder == 0, do: "#{minutes}m", else: "#{minutes}m #{remainder}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    if minutes == 0, do: "#{hours}h", else: "#{hours}h #{minutes}m"
  end

  defp round_number(number, precision) when is_integer(number),
    do: Float.round(number / 1, precision)

  defp round_number(number, precision) when is_float(number), do: Float.round(number, precision)
end
