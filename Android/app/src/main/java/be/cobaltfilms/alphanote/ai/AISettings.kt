package be.cobaltfilms.alphanote.ai

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import be.cobaltfilms.alphanote.data.alphaNoteSettingsDataStore
import be.cobaltfilms.alphanote.services.SecurePasswordStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

data class AISettings(
    val enabled: Boolean = false,
    val jevUrl: String = AISettingsRepository.JEV_URL_DEFAULT,
    val jevDelaiMs: Int = AISettingsRepository.JEV_DELAI_DEFAULT,
    /** Exception au contrat JEV : l'IA peut rédiger une formule en mode math. */
    val formulaDraftEnabled: Boolean = true,
    /** Jeton de service Cloudflare Access ; vides pour un serveur local ou Tailscale. */
    val accessClientId: String = "",
    val accessClientSecret: String = ""
) {
    val accessHeaders: Map<String, String>
        get() = if (accessClientId.isBlank() || accessClientSecret.isBlank()) emptyMap()
        else mapOf("CF-Access-Client-Id" to accessClientId.trim(), "CF-Access-Client-Secret" to accessClientSecret.trim())

    /** Configuration effective, null si l'IA est désactivée ou sans URL. */
    val config: JEVConfig?
        get() {
            if (!enabled) return null
            val url = jevUrl.trim().trimEnd('/')
            if (url.isEmpty()) return null
            return JEVConfig(url, if (jevDelaiMs > 0) jevDelaiMs else AISettingsRepository.JEV_DELAI_DEFAULT, accessHeaders)
        }
}

class AISettingsRepository(context: Context) {
    private val dataStore = context.applicationContext.alphaNoteSettingsDataStore
    // Le secret du jeton reste dans le Keystore, comme le mot de passe Nextcloud.
    private val accessSecretStore = SecurePasswordStore(context, slot = "jev_access")

    val settings: Flow<AISettings> = dataStore.data.map { prefs ->
        AISettings(
            enabled = prefs[ENABLED] ?: false,
            jevUrl = prefs[JEV_URL] ?: JEV_URL_DEFAULT,
            jevDelaiMs = prefs[JEV_DELAI] ?: JEV_DELAI_DEFAULT,
            formulaDraftEnabled = prefs[FORMULA_DRAFT] ?: true,
            accessClientId = prefs[ACCESS_CLIENT_ID] ?: "",
            accessClientSecret = accessSecretStore.readPassword().orEmpty()
        )
    }

    suspend fun current(): AISettings = settings.first()
    suspend fun setEnabled(enabled: Boolean) { dataStore.edit { it[ENABLED] = enabled } }
    suspend fun setJevUrl(url: String) { dataStore.edit { it[JEV_URL] = url.trim() } }
    suspend fun setJevDelaiMs(ms: Int) { dataStore.edit { it[JEV_DELAI] = ms.coerceIn(1000, 120_000) } }
    suspend fun setAccessToken(clientId: String, secret: String) {
        if (secret.isBlank()) accessSecretStore.clearPassword() else accessSecretStore.savePassword(secret.trim())
        dataStore.edit { it[ACCESS_CLIENT_ID] = clientId.trim() }
    }
    suspend fun setFormulaDraftEnabled(enabled: Boolean) { dataStore.edit { it[FORMULA_DRAFT] = enabled } }

    companion object {
        const val JEV_URL_DEFAULT = "http://192.168.3.169:8096"
        const val JEV_DELAI_DEFAULT = 20_000
        private val ENABLED = booleanPreferencesKey("jev_enabled")
        private val JEV_URL = stringPreferencesKey("jev_url")
        private val JEV_DELAI = intPreferencesKey("jev_delai_ms")
        private val FORMULA_DRAFT = booleanPreferencesKey("ai_formula_draft_enabled")
        private val ACCESS_CLIENT_ID = stringPreferencesKey("jev_access_client_id")
    }
}
