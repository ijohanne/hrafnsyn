package io.hrafnsyn.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.hrafnsyn.core.SavedSession
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only ciphertext enters preferences. The origin is authenticated as AES-GCM AAD. */
class SessionStore(context: Context) {
    private val preferences = context.getSharedPreferences("sessions", Context.MODE_PRIVATE)
    private val alias = "io.hrafnsyn.mobile.session-key.v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    private fun slot(origin: String) = MessageDigest.getInstance("SHA-256")
        .digest(origin.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    @Synchronized fun read(origin: String): SavedSession? {
        val encoded = preferences.getString(slot(origin), null) ?: return null
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        require(bytes.size > 28) { "Saved login is damaged. Forget it and sign in again." }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(origin.toByteArray(Charsets.UTF_8))
        val value = JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        return SavedSession(value.getString("access"), value.getString("refresh"),
            value.getLong("accessExpiry"), value.getLong("refreshExpiry"),
            value.getString("session"), value.getString("username"))
    }

    @Synchronized fun write(origin: String, session: SavedSession?) {
        if (session == null) {
            check(preferences.edit().remove(slot(origin)).commit()) { "Unable to remove saved login." }
            return
        }
        val data = JSONObject().put("access", session.accessToken).put("refresh", session.refreshToken)
            .put("accessExpiry", session.accessExpiresAt).put("refreshExpiry", session.refreshExpiresAt)
            .put("session", session.sessionId).put("username", session.username).toString().toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(origin.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.iv + cipher.doFinal(data)
        check(preferences.edit().putString(slot(origin), Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit()) {
            "Unable to save login securely."
        }
    }
}
