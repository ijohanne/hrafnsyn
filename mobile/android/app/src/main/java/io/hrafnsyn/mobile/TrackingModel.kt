package io.hrafnsyn.mobile

import android.app.Application
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.hrafnsyn.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

enum class Phase { SERVER, CONNECTING, LOGIN, TRACKING }
enum class VehicleFilter(val label: String) { ALL("All"), AIRCRAFT("Aircraft"), VESSELS("Vessels") }

class TrackingModel(application: Application) : AndroidViewModel(application) {
    private val preferences = application.getSharedPreferences("settings", 0)
    private val sessions = SessionRepository.get(application)
    private var generation = UUID.randomUUID()
    private var selectionRequest = UUID.randomUUID()
    private var client: TrackingClient? = null
    private var refreshOwner: UUID? = null
    var server by mutableStateOf(preferences.getString("server", "") ?: "")
    var username by mutableStateOf("")
    var phase by mutableStateOf(Phase.SERVER); private set
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var tracks by mutableStateOf<List<Track>>(emptyList()); private set
    var selectedId by mutableStateOf<String?>(null); private set
    var details by mutableStateOf<TrackDetails?>(null); private set
    var loadingDetails by mutableStateOf(false); private set
    var updatedAt by mutableStateOf<Long?>(null); private set
    var reconnecting by mutableStateOf(false); private set
    var query by mutableStateOf("")
    var filter by mutableStateOf(VehicleFilter.ALL)
    val selectedTrack get() = tracks.firstOrNull { it.id == selectedId } ?: details?.track
    val visibleTracks get() = tracks.filter { track ->
        (filter == VehicleFilter.ALL || (filter == VehicleFilter.AIRCRAFT) == track.isAircraft) &&
            (query.isBlank() || listOf(track.name, track.identity, track.registration, track.callsign, track.destination)
                .any { it.contains(query, ignoreCase = true) })
    }.sortedBy { it.name.lowercase() }

    fun connect() = viewModelScope.launch {
        if (busy) return@launch
        busy = true; error = null; phase = Phase.CONNECTING
        generation = UUID.randomUUID()
        val owner = generation
        var connection: TrackingClient? = null
        try {
            val origin = normalizeServer(server)
            server = origin
            // Reuse the same core for an origin while an older request may still
            // be rotating its token. Never reload a superseded pair from disk.
            val active = sessions.client(origin)
            if (generation != owner) return@launch
            connection = active
            client = active
            val (status, session) = perform(active) { active.connect() }
            if (generation != owner) return@launch
            username = session?.username ?: ""
            preferences.edit().putString("server", origin).apply()
            phase = if (status.authRequired && !status.authenticated) Phase.LOGIN else Phase.TRACKING
            if (phase == Phase.TRACKING) refresh()
        } catch (e: Exception) { handle(e, connection, owner, Phase.SERVER) }
        finally { if (generation == owner) busy = false }
    }

    fun login(password: String) = viewModelScope.launch {
        val connection = client ?: return@launch
        if (busy) return@launch
        val owner = generation
        busy = true; error = null
        try {
            val (_, session) = perform(connection) { connection.login(username.trim(), password) }
            if (generation != owner) return@launch
            username = session?.username ?: username
            phase = Phase.TRACKING
            refresh()
        } catch (e: Exception) { handle(e, connection, owner, Phase.LOGIN) }
        finally { if (generation == owner) busy = false }
    }

    suspend fun refresh() {
        val connection = client ?: return
        val owner = generation
        if (phase != Phase.TRACKING || refreshOwner == owner) return
        refreshOwner = owner
        try {
            val (incoming, _) = perform(connection) { connection.activeTracks() }
            if (generation != owner) return
            tracks = incoming
            updatedAt = System.currentTimeMillis(); reconnecting = false; error = null
        } catch (e: Exception) {
            handle(e, connection, owner, Phase.TRACKING)
            if (generation == owner && phase == Phase.TRACKING) reconnecting = true
        } finally { if (refreshOwner == owner) refreshOwner = null }
    }

    fun retry() = viewModelScope.launch { refresh() }
    fun select(id: String) = viewModelScope.launch {
        val connection = client ?: return@launch
        val owner = generation
        val request = UUID.randomUUID().also { selectionRequest = it }
        selectedId = id; details = null; loadingDetails = true
        try {
            val (result, _) = perform(connection) { connection.trackDetails(id) }
            if (owner == generation && request == selectionRequest) details = result
        } catch (e: Exception) { handle(e, connection, owner, Phase.TRACKING, request) }
        finally { if (request == selectionRequest) loadingDetails = false }
    }

    fun clearSelection() {
        selectionRequest = UUID.randomUUID(); selectedId = null; details = null; loadingDetails = false
    }
    fun changeServer() {
        generation = UUID.randomUUID(); client = null; busy = false; phase = Phase.SERVER
        clearSelection(); tracks = emptyList(); updatedAt = null; error = null; reconnecting = false
        username = ""; query = ""; filter = VehicleFilter.ALL
    }
    fun forgetSavedLogin() = viewModelScope.launch {
        try {
            val origin = normalizeServer(server)
            sessions.forget(origin)
            error = null
        } catch (_: Exception) { error = "Could not remove the saved login. Check the server address and try again." }
    }
    fun signOut() = viewModelScope.launch {
        val connection = client ?: return@launch
        if (busy) return@launch
        busy = true
        try {
            sessions.forget(connection.server())
        } catch (_: Exception) { busy = false; error = "Could not remove the saved login. Try again."; return@launch }
        changeServer()
        val owner = generation
        busy = true
        try { connection.signOut() }
        catch (_: Exception) {
            if (generation == owner) error = "Signed out on this device. Server revocation could not be confirmed; revoke the session in account settings if needed."
        } finally { if (generation == owner) busy = false }
    }

    // RPCs have bounded deadlines in the shared core. Let a started rotation and
    // its durable write finish even when the screen/background job is cancelled.
    private suspend fun <T> perform(connection: TrackingClient, request: suspend () -> T): Pair<T, SavedSession?> {
        val result = withContext(NonCancellable) {
            var saved: SavedSession? = null
            val value = try { request() } finally { saved = sessions.persist(connection) }
            value to saved
        }
        currentCoroutineContext().ensureActive()
        return result
    }
    private suspend fun handle(e: Exception, connection: TrackingClient?, owner: UUID, fallback: Phase, selection: UUID? = null) {
        if (e is CancellationException) throw e
        if (generation != owner || (selection != null && selection != selectionRequest)) return
        if (e is ClientException.SignInRequired) {
            phase = Phase.LOGIN; clearSelection(); tracks = emptyList(); updatedAt = null
            error = "Your session expired. Sign in again."
        } else {
            phase = fallback
            error = when (e) {
                is ClientException.InvalidCredentials -> "The username or password is incorrect."
                is ClientException.InvalidServer -> e.reason
                is ClientException.Connection -> e.reason
                is ClientException.Server -> e.reason
                else -> "Could not load the saved login securely. Unlock this device or forget the saved login, then retry."
            }
        }
    }
}
