// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/hrafnsyn"
import topbar from "../vendor/topbar"

const PreserveScroll = {
  mounted() {
    this.windowScroll = {x: 0, y: 0}
    this.containerScroll = new Map()
    this.detailsState = new Map()
  },

  beforeUpdate() {
    this.windowScroll = {x: window.scrollX, y: window.scrollY}
    this.containerScroll = new Map(
      [...this.el.querySelectorAll("[data-preserve-scroll][id]")].map(node => [
        node.id,
        {left: node.scrollLeft, top: node.scrollTop},
      ]),
    )
    this.detailsState = new Map(
      [...this.el.querySelectorAll("details[data-preserve-open][id]")].map(node => [
        node.id,
        node.open,
      ]),
    )
  },

  updated() {
    window.requestAnimationFrame(() => {
      this.detailsState.forEach((open, id) => {
        const node = document.getElementById(id)
        if (!node) return
        node.open = open
      })

      window.scrollTo(this.windowScroll.x, this.windowScroll.y)

      this.containerScroll.forEach((position, id) => {
        const node = document.getElementById(id)
        if (!node) return
        node.scrollLeft = position.left
        node.scrollTop = position.top
      })
    })
  },
}

const TrackingMap = {
  mounted() {
    this.pendingPayload = null
    this.lastSelectedTrackId = null
    this.activePopupTrackId = null
    this.popupPinned = false
    this.hoveredTrackId = null
    this.usesSymbolIcons = false

    this.map = new window.maplibregl.Map({
      container: this.el,
      style: this.el.dataset.styleUrl,
      center: [-5.3, 36.1],
      zoom: 8.1,
      pitch: 0,
      attributionControl: true,
    })

    this.map.addControl(new window.maplibregl.NavigationControl({visualizePitch: true}), "top-right")
    this.map.addControl(new window.maplibregl.ScaleControl({unit: "metric"}), "bottom-right")
    this.popup = new window.maplibregl.Popup({
      closeButton: true,
      closeOnClick: false,
      offset: 18,
      className: "track-popup",
      maxWidth: "22rem",
    })
    this.popup.on("close", () => {
      this.activePopupTrackId = null
      this.popupPinned = false
    })

    this.map.on("load", async () => {
      this.map.addSource("tracks", {
        type: "geojson",
        data: this.emptyCollection(),
      })

      this.map.addSource("selected-route", {
        type: "geojson",
        data: this.emptyCollection(),
      })

      this.map.addSource("selected-route-points", {
        type: "geojson",
        data: this.emptyCollection(),
      })

      this.map.addLayer({
        id: "route-layer",
        type: "line",
        source: "selected-route",
        paint: {
          "line-color": "#f4c95d",
          "line-width": 3.25,
          "line-opacity": 0.9,
        },
      })

      this.map.addLayer({
        id: "route-points-layer",
        type: "circle",
        source: "selected-route-points",
        paint: {
          "circle-radius": 4,
          "circle-color": "#f4c95d",
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#fff7d6",
          "circle-opacity": 0.95,
        },
      })

      this.usesSymbolIcons = await this.installTrackIcons()

      this.map.addLayer({
        id: "tracks-selected-halo",
        type: "circle",
        source: "tracks",
        filter: ["==", ["get", "selected"], true],
        paint: {
          "circle-radius": 16,
          "circle-color": "rgba(244, 201, 93, 0.18)",
          "circle-stroke-width": 2,
          "circle-stroke-color": "#f4c95d",
          "circle-opacity": 1,
        },
      })

      if (this.usesSymbolIcons) {
        this.map.addLayer({
          id: "tracks-layer",
          type: "symbol",
          source: "tracks",
          layout: {
            "icon-image": [
              "match",
              ["get", "vehicle_type"],
              "plane",
              "track-plane",
              "track-vessel",
            ],
            "icon-size": [
              "case",
              ["==", ["get", "selected"], true],
              1.2,
              1,
            ],
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
            "icon-rotation-alignment": "map",
            "icon-rotate": ["coalesce", ["get", "heading"], 0],
          },
        })
      } else {
        this.map.addLayer({
          id: "tracks-layer",
          type: "circle",
          source: "tracks",
          paint: {
            "circle-radius": [
              "case",
              ["==", ["get", "selected"], true],
              9,
              ["==", ["get", "vehicle_type"], "plane"],
              6.5,
              7,
            ],
            "circle-color": [
              "match",
              ["get", "vehicle_type"],
              "plane",
              "#64d2ff",
              "#f97316",
            ],
            "circle-stroke-width": 1.75,
            "circle-stroke-color": "#f8fcff",
            "circle-opacity": 0.92,
          },
        })
      }

      this.map.addLayer({
        id: "tracks-labels",
        type: "symbol",
        source: "tracks",
        layout: {
          "text-field": ["get", "label_text"],
          "text-size": 12,
          "text-font": ["Open Sans Regular"],
          "text-offset": [0, 1.6],
          "text-anchor": "top",
          "text-max-width": 14,
          "text-optional": true,
        },
        paint: {
          "text-color": this.el.dataset.glyphColor || "#d9f0ff",
          "text-halo-color": "#06131f",
          "text-halo-width": 1.2,
          "text-opacity": 0.9,
        },
      })

      this.map.on("click", "tracks-layer", event => {
        const feature = event.features?.[0]
        if (!feature?.properties?.id) return
        this.pinPopup(feature)
        this.pushEvent("select_track", {id: feature.properties.id})
      })

      this.map.on("mouseenter", "tracks-layer", event => {
        const feature = event.features?.[0]
        if (!feature?.properties?.id) return

        this.hoveredTrackId = feature.properties.id
        this.openPopup(feature, false)
        this.map.getCanvas().style.cursor = "pointer"
      })

      this.map.on("mousemove", "tracks-layer", event => {
        if (this.popupPinned) return

        const feature = event.features?.[0]
        if (!feature?.properties?.id) return

        this.hoveredTrackId = feature.properties.id
        this.openPopup(feature, false)
      })

      this.map.on("mouseenter", "tracks-layer", () => {
        this.map.getCanvas().style.cursor = "pointer"
      })

      this.map.on("mouseleave", "tracks-layer", () => {
        this.hoveredTrackId = null
        if (!this.popupPinned) this.popup.remove()
        this.map.getCanvas().style.cursor = ""
      })

      if (this.pendingPayload) {
        this.sync(this.pendingPayload)
      }
    })

    this.handleEvent("map:sync", payload => this.sync(payload))
  },

  destroyed() {
    if (this.map) this.map.remove()
  },

  sync(payload) {
    if (!this.map?.isStyleLoaded()) {
      this.pendingPayload = payload
      return
    }

    this.pendingPayload = payload

    const trackFeatures = payload.tracks
      .filter(track => typeof track.latitude === "number" && typeof track.longitude === "number")
      .map(track => ({
        type: "Feature",
        properties: {
          id: track.id,
          identity: track.identity,
          display_name: track.display_name,
          vehicle_type: track.vehicle_type,
          label_text: this.trackLabel(track, payload.selected_track_id),
          speed_label: this.formatSpeed(track.speed),
          heading_label: this.formatHeading(track.heading),
          altitude_label: this.formatAltitude(track.altitude),
          heading: track.heading,
          destination: track.destination || "",
          callsign: track.callsign || "",
          registration: track.registration || "",
          country: track.country || "",
          status: track.status || "",
          source_name: track.source_name || "",
          observed_at: track.observed_at,
          selected: payload.selected_track_id === track.id,
        },
        geometry: {
          type: "Point",
          coordinates: [track.longitude, track.latitude],
        },
      }))

    const routeFeatures =
      payload.route.length > 1
        ? [{
            type: "Feature",
            properties: {},
            geometry: {
              type: "LineString",
              coordinates: payload.route.map(point => [point.longitude, point.latitude]),
            },
          }]
        : []

    const routePointFeatures = payload.route.map(point => ({
      type: "Feature",
      properties: {
        observed_at: point.observed_at,
      },
      geometry: {
        type: "Point",
        coordinates: [point.longitude, point.latitude],
      },
    }))

    this.map.getSource("tracks").setData({
      type: "FeatureCollection",
      features: trackFeatures,
    })

    this.map.getSource("selected-route").setData({
      type: "FeatureCollection",
      features: routeFeatures,
    })

    this.map.getSource("selected-route-points").setData({
      type: "FeatureCollection",
      features: routePointFeatures,
    })

    if (payload.selected_track_id && payload.selected_track_id !== this.lastSelectedTrackId && routeFeatures.length > 0) {
      const bounds = new window.maplibregl.LngLatBounds()
      routeFeatures[0].geometry.coordinates.forEach(coord => bounds.extend(coord))
      this.map.fitBounds(bounds, {padding: 80, duration: 900, maxZoom: 12.5})
    } else if (payload.selected_track_id && payload.selected_track_id !== this.lastSelectedTrackId) {
      const selectedTrack = payload.tracks.find(track => track.id === payload.selected_track_id)

      if (selectedTrack && typeof selectedTrack.latitude === "number" && typeof selectedTrack.longitude === "number") {
        this.map.flyTo({
          center: [selectedTrack.longitude, selectedTrack.latitude],
          zoom: Math.max(this.map.getZoom(), 9.8),
          duration: 900,
          essential: true,
        })
      }
    }

    this.refreshPopup(trackFeatures, payload.selected_track_id)
    this.lastSelectedTrackId = payload.selected_track_id
  },

  emptyCollection() {
    return {type: "FeatureCollection", features: []}
  },

  async installTrackIcons() {
    const results = await Promise.all([
      this.loadSvgIcon("track-plane", this.buildPlaneIcon("#64d2ff")),
      this.loadSvgIcon("track-vessel", this.buildVesselIcon("#f97316")),
    ])

    return results.every(Boolean)
  },

  loadSvgIcon(name, svg) {
    if (this.map.hasImage(name)) return Promise.resolve(true)

    return new Promise((resolve, reject) => {
      const image = new Image(54, 54)
      image.onload = () => {
        try {
          if (!this.map.hasImage(name)) this.map.addImage(name, image, {pixelRatio: 2})
          resolve(true)
        } catch (_error) {
          resolve(false)
        }
      }
      image.onerror = () => resolve(false)
      image.src = this.svgToDataUrl(svg)
    })
  },

  svgToDataUrl(svg) {
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
  },

  buildPlaneIcon(fill) {
    return `
      <svg xmlns="http://www.w3.org/2000/svg" width="54" height="54" viewBox="0 0 54 54">
        <g transform="translate(27 27)">
          <path d="M0 -22L4 -8L15 -4L15 1L4 0L2 8L8 15L8 19L0 14L-8 19L-8 15L-2 8L-4 0L-15 1L-15 -4L-4 -8L0 -22Z"
            fill="${fill}" stroke="#ecfeff" stroke-width="2" stroke-linejoin="round"/>
        </g>
      </svg>
    `
  },

  buildVesselIcon(fill) {
    return `
      <svg xmlns="http://www.w3.org/2000/svg" width="54" height="54" viewBox="0 0 54 54">
        <g transform="translate(27 27)">
          <path d="M0 -18L7 -5L7 3L13 7L11 14L0 18L-11 14L-13 7L-7 3L-7 -5L0 -18Z"
            fill="${fill}" stroke="#fff0df" stroke-width="2" stroke-linejoin="round"/>
          <path d="M0 -9L4 -1H-4L0 -9Z" fill="#fff0df"/>
        </g>
      </svg>
    `
  },

  trackLabel(track, selectedTrackId) {
    if (track.id === selectedTrackId) return track.display_name
    if (track.vehicle_type === "plane") return track.display_name
    return ""
  },

  openPopup(feature, pinned) {
    const coordinates = feature.geometry?.coordinates
    if (!Array.isArray(coordinates)) return

    this.activePopupTrackId = feature.properties.id
    this.popupPinned = pinned
    this.popup
      .setLngLat(coordinates)
      .setHTML(this.popupMarkup(feature.properties))
      .addTo(this.map)
  },

  pinPopup(feature) {
    this.openPopup(feature, true)
  },

  refreshPopup(trackFeatures, selectedTrackId) {
    if (
      selectedTrackId &&
      (selectedTrackId !== this.lastSelectedTrackId ||
        (this.popupPinned && this.activePopupTrackId === selectedTrackId))
    ) {
      const selectedFeature = trackFeatures.find(track => track.properties.id === selectedTrackId)

      if (selectedFeature) {
        this.openPopup(selectedFeature, true)
        return
      }
    }

    const targetId = this.popupPinned ? this.activePopupTrackId : this.hoveredTrackId

    if (!targetId) {
      if (!this.popupPinned) this.popup.remove()
      return
    }

    const feature = trackFeatures.find(track => track.properties.id === targetId)

    if (!feature) {
      this.popup.remove()
      this.activePopupTrackId = null
      this.popupPinned = false
      return
    }

    this.openPopup(feature, this.popupPinned && feature.properties.id === targetId)
  },

  popupMarkup(properties) {
    const metrics = [
      {label: "Speed", value: properties.speed_label},
      {label: "Heading", value: properties.heading_label},
      {label: properties.vehicle_type === "plane" ? "Altitude" : "Status", value: properties.vehicle_type === "plane" ? properties.altitude_label : (properties.status || "-")},
    ]

    const meta = [
      properties.destination ? {label: "Destination", value: properties.destination} : null,
      properties.callsign ? {label: "Callsign", value: properties.callsign} : null,
      properties.registration ? {label: properties.vehicle_type === "plane" ? "Registration" : "IMO", value: properties.registration} : null,
      properties.source_name ? {label: "Feed", value: properties.source_name} : null,
      {label: "Seen", value: this.formatAge(properties.observed_at)},
    ].filter(Boolean)

    return `
      <article class="track-popup-card ${properties.vehicle_type}">
        <div class="track-popup-top">
          <span class="track-popup-badge">${properties.vehicle_type === "plane" ? "Aircraft" : "Vessel"}</span>
          <span class="track-popup-age">${this.escapeHtml(this.formatAge(properties.observed_at))}</span>
        </div>
        <strong>${this.escapeHtml(properties.display_name)}</strong>
        <p>${this.escapeHtml(properties.identity)}</p>
        <div class="track-popup-metrics">
          ${metrics.map(metric => `
            <div>
              <span>${this.escapeHtml(metric.label)}</span>
              <strong>${this.escapeHtml(metric.value)}</strong>
            </div>
          `).join("")}
        </div>
        <dl class="track-popup-meta">
          ${meta.map(item => `
            <div>
              <dt>${this.escapeHtml(item.label)}</dt>
              <dd>${this.escapeHtml(item.value)}</dd>
            </div>
          `).join("")}
        </dl>
      </article>
    `
  },

  formatSpeed(value) {
    if (value === null || value === undefined || value === "") return "-"
    return `${Math.round(Number(value))} kt`
  },

  formatHeading(value) {
    if (value === null || value === undefined || value === "") return "-"
    return `${Math.round(Number(value))}°`
  },

  formatAltitude(value) {
    if (value === null || value === undefined || value === "") return "-"
    if (Number(value) === 0) return "surface"
    return `${Math.round(Number(value))} ft`
  },

  formatAge(value) {
    if (!value) return "-"

    const observedAt = new Date(value)
    const seconds = Math.max(0, Math.round((Date.now() - observedAt.getTime()) / 1000))

    if (seconds < 60) return `${seconds}s ago`
    if (seconds < 3600) return `${Math.round(seconds / 60)}m ago`
    return `${Math.round(seconds / 3600)}h ago`
  },

  escapeHtml(value) {
    return String(value ?? "-")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;")
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, PreserveScroll, TrackingMap},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#f4c95d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
