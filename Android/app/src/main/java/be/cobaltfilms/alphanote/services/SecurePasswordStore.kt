package be.cobaltfilms.alphanote.services

import android.content.Context
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stockage de mot de passe avec fallback robuste.
 * Essaye Android Keystore (AES/GCM), si ça échoue utilise SharedPreferences en clair avec warning.
 */
class SecurePasswordStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var keystoreFailed = false

    companion object {
        private const val TAG = "SecurePasswordStore"
        private const val PREFS_NAME = "alphanote_secure_passwords"
        private const val PASSWORD_KEY = "nextcloud_password"
        private const val PASSWORD_FALLBACK = "nextcloud_password_fb"
        private const val IV_KEY = "nextcloud_password_iv"
        private const val KEY_ALIAS = "AlphaNoteNextcloudPasswordKey"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
    }

    init {
        keystoreFailed = prefs.getBoolean("keystore_failed", false)
    }

    fun savePassword(password: String) {
        if (password.isBlank()) {
            clearPassword()
            return
        }

        if (!keystoreFailed) {
            try {
                saveWithKeystore(password)
                return
            } catch (e: Exception) {
                Log.w(TAG, "Keystore failed, falling back to plain storage", e)
                keystoreFailed = true
                prefs.edit().putBoolean("keystore_failed", true).apply()
            }
        }

        saveFallback(password)
    }

    fun readPassword(): String? {
        if (!keystoreFailed) {
            try {
                return readWithKeystore()
            } catch (e: Exception) {
                Log.w(TAG, "Keystore read failed, trying fallback", e)
            }
        }
        return readFallback()
    }

    fun clearPassword() {
        prefs.edit()
            .remove(IV_KEY)
            .remove(PASSWORD_KEY)
            .remove(PASSWORD_FALLBACK)
            .remove("keystore_failed")
            .apply()
    }

    fun isUsingFallback(): Boolean = keystoreFailed

    private fun saveWithKeystore(password: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(password.toByteArray(Charsets.UTF_8))

        prefs.edit()
            .putString(IV_KEY, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(PASSWORD_KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .remove(PASSWORD_FALLBACK)
            .apply()
    }

    private fun readWithKeystore(): String? {
        val iv = prefs.getString(IV_KEY, null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: return null
        val encrypted = prefs.getString(PASSWORD_KEY, null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: return null

        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    private fun saveFallback(password: String) {
        prefs.edit()
            .putString(PASSWORD_FALLBACK, password)
            .remove(IV_KEY)
            .remove(PASSWORD_KEY)
            .apply()
    }

    private fun readFallback(): String? {
        return prefs.getString(PASSWORD_FALLBACK, null)
    }

    @Suppress("DEPRECATION")
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }

        val generator = KeyGenerator.getInstance("AES", ANDROID_KEYSTORE)
        val spec = android.security.keystore.KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()

        generator.init(spec)
        return generator.generateKey()
    }
}
