package io.hrafnsyn.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.hrafnsyn.core.Track
import kotlinx.coroutines.delay
import org.maplibre.android.MapLibre
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        MapLibre.getInstance(this)
        setContent {
            val dark = isSystemInDarkTheme()
            val colors = if (dark) darkColorScheme(primary = Color(0xff7dd3de), onPrimary = Color(0xff00363d),
                secondary = Color(0xffb9cbd0), tertiary = Color(0xfff4b48b),
                background = Color(0xff111719), surface = Color(0xff111719),
                surfaceContainerLow = Color(0xff192124), surfaceContainer = Color(0xff1d272a),
                surfaceContainerHigh = Color(0xff263135), secondaryContainer = Color(0xff30474d),
                onSecondaryContainer = Color(0xffd8edf0), onSurface = Color(0xffe1e8e8), onSurfaceVariant = Color(0xffb9c7ca))
            else lightColorScheme(primary = Color(0xff0b6570), onPrimary = Color.White,
                secondary = Color(0xff4c6268), tertiary = Color(0xff9c4a1a),
                background = Color(0xfff7f9f8), surface = Color(0xfff7f9f8),
                surfaceContainerLow = Color(0xfff0f4f3), surfaceContainer = Color(0xffeaf0ef),
                surfaceContainerHigh = Color(0xffe2eae8), secondaryContainer = Color(0xffd7e9e9),
                onSecondaryContainer = Color(0xff1a393e), onSurface = Color(0xff182427), onSurfaceVariant = Color(0xff4c6268))
            MaterialTheme(colorScheme = colors) {
                val model: TrackingModel = viewModel()
                var restored by rememberSaveable { mutableStateOf(false) }
                val lifecycle = LocalLifecycleOwner.current.lifecycle
                LaunchedEffect(model) {
                    if (!restored) {
                        restored = true
                        if (BuildConfig.DEBUG) intent.getStringExtra("server")?.let { model.server = it }
                        if (model.server.isNotBlank()) model.connect()
                    }
                }
                LaunchedEffect(lifecycle, model) {
                    lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                        while (true) {
                            model.retry()
                            delay(if (model.reconnecting) 15_000 else 5_000)
                        }
                    }
                }
                Surface(Modifier.fillMaxSize()) {
                    if (model.phase == Phase.TRACKING) TrackingScreen(model, dark)
                    else ConnectionScreen(model)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ConnectionScreen(model: TrackingModel) {
    var password by remember { mutableStateOf("") }
    val login = model.phase == Phase.LOGIN
    BackHandler(login && !model.busy) { model.changeServer() }
    Scaffold(topBar = {
        TopAppBar(title = { Text(if (login) "Sign in" else "Hrafnsyn") }, navigationIcon = {
            if (login) IconButton(onClick = { model.changeServer() }, enabled = !model.busy) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Change server")
            }
        })
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState())
            .padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(if (login) "This server requires a login" else "Connect to your server", style = MaterialTheme.typography.headlineSmall)
                Text(if (login) model.server else "Use your Hrafnsyn gRPC address. Public servers open directly; restricted servers ask you to sign in.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (!login) {
                    OutlinedTextField(value = model.server, onValueChange = { model.server = it },
                        label = { Text("Server address") }, placeholder = { Text("https://hrafnsyn.unixpimps.net") },
                        singleLine = true, enabled = !model.busy, modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                    Text("HTTPS is required. Use the gRPC port if your server exposes it separately.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    OutlinedTextField(model.username, { model.username = it }, Modifier.fillMaxWidth(),
                        label = { Text("Username") }, singleLine = true, enabled = !model.busy)
                    OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("Password") },
                        singleLine = true, enabled = !model.busy, visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                    Text("Your session is saved securely on this device. Your password is not stored.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                model.error?.let { ErrorNotice(it) }
                Button(onClick = {
                    if (login) { model.login(password); password = "" } else model.connect()
                }, enabled = !model.busy && if (login) model.username.isNotBlank() && password.isNotEmpty() else model.server.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    if (model.busy) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(12.dp))
                    }
                    Text(if (model.busy) "Connecting…" else if (login) "Sign in" else "Connect")
                }
                if (!login && model.server.isNotBlank()) TextButton(onClick = { model.forgetSavedLogin() }, enabled = !model.busy) {
                    Text("Forget saved login for this server")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun TrackingScreen(model: TrackingModel, dark: Boolean) {
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showTraffic by rememberSaveable { mutableStateOf(false) }
    var overview by remember { mutableIntStateOf(0) }
    var mapError by remember { mutableStateOf(false) }
    var mapLoading by remember { mutableStateOf(true) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(5_000); now = System.currentTimeMillis() } }
    if (showSettings) {
        BackHandler { showSettings = false }
        Scaffold(topBar = { TopAppBar(title = { Text("Server") }, navigationIcon = {
            IconButton({ showSettings = false }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to map") }
        }) }) { padding ->
            Column(Modifier.padding(padding).padding(24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text(model.server, style = MaterialTheme.typography.titleMedium)
                Text(if (model.username.isBlank()) "Public access" else "Signed in as ${model.username}", style = MaterialTheme.typography.bodyLarge)
                OutlinedButton({ showSettings = false; model.changeServer() }) { Text("Change server") }
                if (model.username.isNotBlank()) Button({ showSettings = false; model.signOut() }, enabled = !model.busy) { Text("Sign out") }
                Text("Changing servers keeps each server’s saved login separate. Signing out removes this server’s login from this device.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val expanded = maxWidth >= 840.dp
        val threeColumns = maxWidth >= 1200.dp
        BackHandler(model.selectedId != null || showTraffic) {
            if (model.selectedId != null) model.clearSelection() else showTraffic = false
        }
        Scaffold(topBar = {
            TopAppBar(title = { Text(if (showTraffic && !expanded) "Traffic" else "Hrafnsyn") }, actions = {
                if (!expanded) IconButton({ showTraffic = !showTraffic }) {
                    Icon(if (showTraffic) Icons.Default.Map else Icons.Default.List, if (showTraffic) "Show map" else "Show traffic")
                }
                IconButton({ showSettings = true }) { Icon(Icons.Default.Settings, "Server settings") }
            })
        }, bottomBar = {
            Surface(tonalElevation = 2.dp) {
                Row(Modifier.navigationBarsPadding().fillMaxWidth().padding(start = 16.dp, end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(if (model.reconnecting) "Reconnecting" else "${model.tracks.size} active", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.weight(1f))
                    model.updatedAt?.let { Text("${((now - it) / 1000).coerceAtLeast(0)}s ago", style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    IconButton({ model.clearSelection(); overview++; showTraffic = false }) { Icon(Icons.Default.ZoomOutMap, "Overview") }
                }
            }
        }) { padding ->
            Column(Modifier.padding(padding)) {
                model.error?.let { ErrorNotice(it, model::retry) }
                if (mapError && !showTraffic) ErrorNotice("Map tiles could not load. Traffic and search are still available.")
                Row(Modifier.weight(1f)) {
                    if (expanded) {
                        Surface(Modifier.width(320.dp).fillMaxHeight(), tonalElevation = 1.dp) {
                            if (!threeColumns && model.selectedId != null) DetailPane(model) else TrafficList(model) { model.select(it) }
                        }
                        VerticalDivider()
                    }
                    if (!expanded && showTraffic) TrafficList(model, Modifier.fillMaxSize()) { model.select(it); showTraffic = false }
                    else Box(Modifier.weight(1f).fillMaxHeight()) {
                        TrafficMap(model.visibleTracks, model.selectedTrack, model.details?.route ?: emptyList(), overview, dark, !expanded && model.selectedId != null,
                            onSelect = { model.select(it) }, onMapError = { mapError = it; mapLoading = false }, Modifier.fillMaxSize())
                        if (mapLoading) CircularProgressIndicator(Modifier.align(Alignment.Center))
                        if (model.tracks.isEmpty() && model.updatedAt != null) Surface(Modifier.align(Alignment.Center).padding(24.dp), tonalElevation = 3.dp) {
                            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("No active traffic", style = MaterialTheme.typography.titleLarge)
                                Text("Contacts appear when this server receives positions.", style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                    if (expanded && threeColumns && model.selectedId != null) {
                        VerticalDivider()
                        Surface(Modifier.width(320.dp).fillMaxHeight(), tonalElevation = 1.dp) { DetailPane(model) }
                    }
                }
            }
        }
        if (!expanded && model.selectedId != null) ModalBottomSheet(onDismissRequest = model::clearSelection) {
            DetailPane(model, Modifier.fillMaxWidth().fillMaxHeight(0.85f))
        }
    }
}

@Composable private fun TrafficList(model: TrackingModel, modifier: Modifier = Modifier, select: (String) -> Unit) {
    Column(modifier) {
        OutlinedTextField(model.query, { model.query = it }, Modifier.fillMaxWidth().padding(12.dp),
            label = { Text("Search traffic") }, singleLine = true, leadingIcon = { Icon(Icons.Default.Search, null) })
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VehicleFilter.entries.forEach { FilterChip(selected = model.filter == it, onClick = { model.filter = it }, label = { Text(it.label) }) }
        }
        val visible = model.visibleTracks
        Text("${visible.size} contacts", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.labelLarge)
        if (visible.isEmpty()) Text(if (model.query.isNotBlank()) "No matching contacts. Try a callsign, registration or identity." else "No contacts in this category.",
            Modifier.padding(24.dp), style = MaterialTheme.typography.bodyLarge)
        LazyColumn(Modifier.weight(1f)) {
            items(visible, key = { it.id }) { track ->
                ListItem(modifier = Modifier.testTag("contact").clickable { select(track.id) }.heightIn(min = 72.dp),
                    headlineContent = { Text(track.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                    supportingContent = { Text("${track.identity} · ${if (track.isAircraft) "Aircraft" else "Vessel"}") },
                    leadingContent = { Icon(if (track.isAircraft) Icons.Default.Flight else Icons.Default.DirectionsBoat, null,
                        tint = if (track.isAircraft) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.tertiary) },
                    trailingContent = { Text("${track.speedKnots.toInt()} kn", style = MaterialTheme.typography.labelLarge) },
                    colors = ListItemDefaults.colors(containerColor = if (model.selectedId == track.id) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surface))
                HorizontalDivider(Modifier.padding(start = 56.dp))
            }
        }
    }
}

@Composable private fun DetailPane(model: TrackingModel, modifier: Modifier = Modifier) {
    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Track details", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            IconButton(model::clearSelection) { Icon(Icons.Default.Close, "Close track details") }
        }
        HorizontalDivider()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            model.selectedTrack?.let { track ->
                Text(track.name, style = MaterialTheme.typography.headlineSmall)
                Text("${track.identity} · ${if (track.isAircraft) "Aircraft" else "Vessel"}", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                DetailValue("Speed", "${track.speedKnots.toInt()} kn")
                DetailValue("Heading", "${track.headingDegrees.toInt()}°")
                if (track.isAircraft) DetailValue("Altitude", "${track.altitudeFeet} ft")
                DetailValue("Position", String.format(Locale.US, "%.4f, %.4f", track.latitude, track.longitude))
                DetailValue("Observed", formatTime(track.observedAt))
                listOf("Callsign" to track.callsign, "Registration" to track.registration, "Country" to track.country,
                    "Destination" to track.destination, "Source" to track.sourceName).filter { it.second.isNotBlank() }.forEach { DetailValue(it.first, it.second) }
                HorizontalDivider()
                Text("Route · last 6 hours", style = MaterialTheme.typography.titleMedium)
                if (model.loadingDetails) LinearProgressIndicator(Modifier.fillMaxWidth())
                model.details?.let {
                    DetailValue("Positions", it.route.size.toString())
                    DetailValue("Distance", String.format(Locale.US, "%.1f km", it.distanceMeters / 1000))
                }
            }
        }
    }
}

@Composable private fun DetailValue(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable private fun ErrorNotice(message: String, retry: (() -> Unit)? = null) {
    Surface(color = MaterialTheme.colorScheme.errorContainer) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(message, color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodyMedium)
            if (retry != null) TextButton(retry) { Text("Retry") }
        }
    }
}

private fun formatTime(seconds: Long): String = DateTimeFormatter.ofPattern("d MMM, HH:mm:ss")
    .withZone(ZoneId.systemDefault()).format(Instant.ofEpochSecond(seconds))
