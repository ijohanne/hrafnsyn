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

const TrackingMap = {
  mounted() {
    this.pendingPayload = null
    this.lastSelectedTrackId = null

    this.map = new window.maplibregl.Map({
      container: this.el,
      style: this.el.dataset.styleUrl,
      center: [-5.3, 36.1],
      zoom: 8.1,
      pitch: 48,
      attributionControl: true,
    })

    this.map.addControl(new window.maplibregl.NavigationControl({visualizePitch: true}), "top-right")
    this.map.addControl(new window.maplibregl.ScaleControl({unit: "metric"}), "bottom-right")

    this.map.on("load", () => {
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

      this.map.addLayer({
        id: "tracks-layer",
        type: "circle",
        source: "tracks",
        paint: {
          "circle-radius": [
            "case",
            ["==", ["get", "selected"], true],
            10,
            ["==", ["get", "vehicle_type"], "plane"],
            6.5,
            7.5,
          ],
          "circle-color": [
            "match",
            ["get", "vehicle_type"],
            "plane",
            "#64d2ff",
            "#f97316",
          ],
          "circle-stroke-width": [
            "case",
            ["==", ["get", "selected"], true],
            3,
            1.5,
          ],
          "circle-stroke-color": "#ecfeff",
          "circle-opacity": 0.9,
        },
      })

      this.map.addLayer({
        id: "tracks-labels",
        type: "symbol",
        source: "tracks",
        layout: {
          "text-field": ["get", "display_name"],
          "text-size": 12,
          "text-font": ["Open Sans Regular"],
          "text-offset": [0, 1.6],
          "text-anchor": "top",
          "text-max-width": 14,
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
        this.pushEvent("select_track", {id: feature.properties.id})
      })

      this.map.on("mouseenter", "tracks-layer", () => {
        this.map.getCanvas().style.cursor = "pointer"
      })

      this.map.on("mouseleave", "tracks-layer", () => {
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

    this.lastSelectedTrackId = payload.selected_track_id
  },

  emptyCollection() {
    return {type: "FeatureCollection", features: []}
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, TrackingMap},
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
