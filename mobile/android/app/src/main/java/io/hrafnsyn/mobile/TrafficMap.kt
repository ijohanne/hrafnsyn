package io.hrafnsyn.mobile

import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.core.content.ContextCompat
import android.graphics.RectF
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.hrafnsyn.core.RoutePoint
import io.hrafnsyn.core.Track
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression.*
import org.maplibre.android.style.layers.*
import org.maplibre.android.style.layers.PropertyFactory.*
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.*

@Composable
fun TrafficMap(tracks: List<Track>, selected: Track?, route: List<RoutePoint>, overview: Int,
               dark: Boolean, compactInspection: Boolean, onSelect: (String) -> Unit, onMapError: (Boolean) -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val view = remember { MapView(context).apply { onCreate(null) } }
    val renderer = remember(view) { TrafficMapRenderer(view) }
    val currentSelect by rememberUpdatedState(onSelect)
    val currentMapError by rememberUpdatedState(onMapError)
    DisposableEffect(view, owner) {
        val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> renderer.viewportChanged() }
        view.addOnLayoutChangeListener(layoutListener)
        val listener = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> view.onStart()
                Lifecycle.Event.ON_RESUME -> view.onResume()
                Lifecycle.Event.ON_PAUSE -> view.onPause()
                Lifecycle.Event.ON_STOP -> view.onStop()
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(listener)
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) view.onStart()
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.onResume()
        view.addOnDidFailLoadingMapListener { currentMapError(true) }
        view.getMapAsync { map ->
            renderer.map = map
            map.addOnMapClickListener { location ->
                val point = map.projection.toScreenLocation(location)
                val radius = 24 * context.resources.displayMetrics.density
                val found = map.queryRenderedFeatures(RectF(point.x - radius, point.y - radius, point.x + radius, point.y + radius),
                    "selected", "contacts", "clusters")
                val contact = found.firstOrNull { it.hasProperty("trackId") }
                if (contact != null) currentSelect(contact.getStringProperty("trackId"))
                else found.firstOrNull { it.hasProperty("cluster_id") }?.let { cluster ->
                    val source = map.style?.getSourceAs<GeoJsonSource>("traffic")
                    val geometry = cluster.geometry() as? Point
                    if (source != null && geometry != null) map.moveCamera(CameraUpdateFactory.newLatLngZoom(
                        LatLng(geometry.latitude(), geometry.longitude()), source.getClusterExpansionZoom(cluster).toDouble() + 0.3))
                }
                found.isNotEmpty()
            }
            renderer.loadStyle(dark) { currentMapError(false) }
        }
        onDispose {
            view.removeOnLayoutChangeListener(layoutListener)
            owner.lifecycle.removeObserver(listener)
            view.onPause(); view.onStop(); view.onDestroy()
        }
    }
    AndroidView(factory = { view }, modifier = modifier, update = {
        renderer.tracks = tracks; renderer.selected = selected; renderer.route = route
        renderer.overview = overview
        renderer.compactInspection = compactInspection
        if (renderer.dark != dark && renderer.map != null) renderer.loadStyle(dark) { currentMapError(false) }
        renderer.sync()
    })
}

private class TrafficMapRenderer(private val view: MapView) {
    var map: MapLibreMap? = null
    var dark = false
    var tracks: List<Track> = emptyList()
    var selected: Track? = null
    var route: List<RoutePoint> = emptyList()
    var overview = 0
    var compactInspection = false
    private var fitted = false
    private var lastOverview = 0
    private var lastSelection: String? = null
    private var ready = false

    fun loadStyle(night: Boolean, loaded: () -> Unit) {
        dark = night; ready = false
        val url = "https://tiles.openfreemap.org/styles/" + if (night) "dark" else "liberty"
        map?.setStyle(Style.Builder().fromUri(url)) { style ->
            fun marker(resource: Int): Bitmap {
                val pixels = (24 * view.resources.displayMetrics.density).toInt()
                val bitmap = Bitmap.createBitmap(pixels, pixels, Bitmap.Config.ARGB_8888)
                bitmap.density = view.resources.displayMetrics.densityDpi
                ContextCompat.getDrawable(view.context, resource)!!.apply {
                    setBounds(0, 0, pixels, pixels); draw(Canvas(bitmap))
                }
                return bitmap
            }
            style.addImage("aircraft", marker(R.drawable.map_aircraft))
            style.addImage("vessel", marker(R.drawable.map_vessel))
            style.addSource(GeoJsonSource("traffic", FeatureCollection.fromFeatures(emptyArray()),
                GeoJsonOptions().withCluster(true).withClusterMaxZoom(14).withClusterRadius(64)))
            style.addSource(GeoJsonSource("selection", FeatureCollection.fromFeatures(emptyArray())))
            style.addSource(GeoJsonSource("route", FeatureCollection.fromFeatures(emptyArray())))
            style.addLayer(LineLayer("route-line", "route").withProperties(lineColor("#e5b84e"), lineWidth(3f)))
            style.addLayer(CircleLayer("clusters", "traffic").withFilter(has("point_count"))
                .withProperties(circleColor(if (night) "#7dd3de" else "#0b6570"), circleRadius(23f)))
            style.addLayer(SymbolLayer("cluster-count", "traffic").withFilter(has("point_count"))
                .withProperties(textField(toString(get("point_count"))), textSize(14f),
                    textFont(arrayOf("Noto Sans Regular")), textAllowOverlap(true),
                    textColor(if (night) "#00363d" else "#ffffff")))
            style.addLayer(CircleLayer("contacts-background", "traffic").withFilter(not(has("point_count")))
                .withProperties(circleColor("#ffffff"), circleRadius(13f)))
            style.addLayer(SymbolLayer("contacts", "traffic").withFilter(not(has("point_count")))
                .withProperties(iconImage(switchCase(get("aircraft"), literal("aircraft"), literal("vessel"))),
                    iconAllowOverlap(true), iconIgnorePlacement(true)))
            style.addLayer(CircleLayer("selected", "selection").withProperties(
                circleColor("#e5b84e"), circleRadius(17f), circleStrokeWidth(2f), circleStrokeColor("#172c31")))
            style.addLayer(SymbolLayer("selected-icon", "selection").withProperties(
                iconImage(switchCase(get("aircraft"), literal("aircraft"), literal("vessel"))),
                iconAllowOverlap(true), iconIgnorePlacement(true)))
            style.addLayer(SymbolLayer("selected-label", "selection").withProperties(
                textField(get("name")), textFont(arrayOf("Noto Sans Regular")), textSize(13f),
                textOffset(arrayOf(0f, 1.8f)), textColor(if (night) "#ffffff" else "#142b31"),
                textHaloColor(if (night) "#142b31" else "#ffffff"), textHaloWidth(1.5f)))
            ready = true; loaded(); sync()
        }
    }

    fun sync() {
        val map = map ?: return
        val style = map.style ?: return
        if (!ready || view.width == 0 || view.height == 0) return
        // The compact inspector initially occupies the lower half. Keep the
        // contact centered in the geography that remains visible above it.
        if (!compactInspection) map.setPadding(0, 0, 0, 0)
        val valid = tracks.filter { it.latitude.isFinite() && it.longitude.isFinite() && it.latitude in -90.0..90.0 && it.longitude in -180.0..180.0 }
        fun feature(track: Track) = Feature.fromGeometry(Point.fromLngLat(track.longitude, track.latitude)).apply {
            addStringProperty("trackId", track.id); addStringProperty("name", track.name); addBooleanProperty("aircraft", track.isAircraft)
        }
        style.getSourceAs<GeoJsonSource>("traffic")?.setGeoJson(FeatureCollection.fromFeatures(valid.filter { it.id != selected?.id }.map(::feature)))
        style.getSourceAs<GeoJsonSource>("selection")?.setGeoJson(FeatureCollection.fromFeatures(selected?.let { listOf(feature(it)) } ?: emptyList()))
        val lines = if (route.size > 1) listOf(Feature.fromGeometry(LineString.fromLngLats(route.map { Point.fromLngLat(it.longitude, it.latitude) }))) else emptyList()
        style.getSourceAs<GeoJsonSource>("route")?.setGeoJson(FeatureCollection.fromFeatures(lines))
        if ((!fitted || lastOverview != overview) && valid.isNotEmpty()) {
            fit(map, valid.map { LatLng(it.latitude, it.longitude) })
            fitted = true; lastOverview = overview
        }
        if (selected?.id != lastSelection) {
            selected?.let { track ->
                if (route.size > 1 && !compactInspection) fit(map, route.map { LatLng(it.latitude, it.longitude) })
                else map.moveCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder()
                    .target(LatLng(track.latitude, track.longitude)).zoom(10.0)
                    .padding(doubleArrayOf(0.0, 0.0, 0.0, if (compactInspection) view.height * 0.5 else 0.0)).build()))
            }
            lastSelection = selected?.id
        }
    }

    fun viewportChanged() {
        if (compactInspection) lastSelection = null
        sync()
    }

    private fun fit(map: MapLibreMap, points: List<LatLng>) {
        if (points.size == 1 || points.all { it == points.first() }) {
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(points.first(), 10.0))
        } else {
            val padding = (32 * view.resources.displayMetrics.density).toInt()
            map.moveCamera(CameraUpdateFactory.newLatLngBounds(LatLngBounds.Builder().includes(points).build(), padding))
        }
    }
}
