package io.hrafnsyn.mobile

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.hrafnsyn.core.SavedSession
import io.hrafnsyn.core.TrackingClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.security.MessageDigest
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SessionStoreTest {
    @Test fun credentialsRoundTripRotateAndRemainIsolatedByOrigin() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = SessionStore(context)
        val origin = "https://test-${UUID.randomUUID()}.invalid"
        val second = "$origin:50051"
        val session = SavedSession("test-access-secret", "test-refresh-secret", 900, 3600, "session", "tester")
        try {
            store.write(origin, session)
            assertEquals(session, store.read(origin))
            assertNull(store.read(second))
            val contents = context.getSharedPreferences("sessions", 0).all.values.joinToString()
            assertFalse(contents.contains("test-access-secret"))
            assertFalse(contents.contains("test-refresh-secret"))
            val rotated = session.copy(accessToken = "rotated-access", refreshToken = "rotated-refresh")
            store.write(origin, rotated)
            assertEquals("rotated-refresh", store.read(origin)?.refreshToken)
            store.write(origin, null)
            assertNull(store.read(origin))
        } finally { store.write(origin, null); store.write(second, null) }
    }

    @Test fun ciphertextCannotBeMovedToAnotherServer() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = SessionStore(context)
        val origin = "https://aad-${UUID.randomUUID()}.invalid"
        val other = "$origin:4433"
        fun slot(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
        val preferences = context.getSharedPreferences("sessions", 0)
        try {
            store.write(origin, SavedSession("access", "refresh", 900, 3600, "session", "tester"))
            preferences.edit().putString(slot(other), preferences.getString(slot(origin), null)).commit()
            assertThrows(Exception::class.java) { store.read(other) }
        } finally { store.write(origin, null); store.write(other, null) }
    }

    @Test fun nativeCoreConnectsToRealGrpcServer() = runBlocking {
        val endpoint = InstrumentationRegistry.getArguments().getString("hrafnsynGrpcEndpoint")
        assumeTrue("Pass hrafnsynGrpcEndpoint to run live transport verification", !endpoint.isNullOrBlank())
        val client = TrackingClient(endpoint!!, null)
        try {
            val status = client.connect()
            assertFalse("Use the local public fixture server for this test", status.authRequired)
            val tracks = client.activeTracks()
            if (tracks.isNotEmpty()) assertNotNull(client.trackDetails(tracks.first().id).track)
        } finally { client.close() }
    }
}
