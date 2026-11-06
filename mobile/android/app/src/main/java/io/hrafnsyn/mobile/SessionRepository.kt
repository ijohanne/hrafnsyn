package io.hrafnsyn.mobile

import android.content.Context
import io.hrafnsyn.core.SavedSession
import io.hrafnsyn.core.TrackingClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Process-wide ownership survives Activity/ViewModel replacement during rotation. */
internal class SessionRepository private constructor(context: Context) {
    private val vault = SessionStore(context.applicationContext)
    private val mutex = Mutex()
    private val clients = mutableMapOf<String, TrackingClient>()

    suspend fun client(origin: String): TrackingClient = mutex.withLock {
        clients[origin] ?: TrackingClient(origin, withContext(Dispatchers.IO) { vault.read(origin) })
            .also { clients[origin] = it }
    }

    suspend fun persist(client: TrackingClient): SavedSession? = mutex.withLock {
        val session = client.savedSession()
        // Any operation on the current core can persist its newest rotated pair.
        // Forgotten/revoked cores cannot resurrect credentials after their removal.
        if (clients[client.server()] === client) {
            withContext(Dispatchers.IO) { vault.write(client.server(), session) }
        }
        session
    }

    suspend fun forget(origin: String) = withContext(NonCancellable) {
        mutex.withLock {
            withContext(Dispatchers.IO) { vault.write(origin, null) }
            clients.remove(origin)
            Unit
        }
    }

    companion object {
        @Volatile private var instance: SessionRepository? = null
        fun get(context: Context): SessionRepository = instance ?: synchronized(this) {
            instance ?: SessionRepository(context).also { instance = it }
        }
    }
}
