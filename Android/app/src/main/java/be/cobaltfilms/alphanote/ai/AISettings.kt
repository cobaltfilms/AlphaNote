package be.cobaltfilms.alphanote.ai

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import be.cobaltfilms.alphanote.data.alphaNoteSettingsDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

data class AISettings(
    val enabled: Boolean = false,
    val jevUrl: String = AISettingsRepository.JEV_URL_DEFAULT,
    val jevDelaiMs: Int = AISettingsRepository.JEV_DELAI_DEFAULT
) {
    /** Configuration effective, null si l'IA est désactivée ou sans URL. */
    val config: JEVConfig?
        get() {
            if (!enabled) return null
            val url = jevUrl.trim().trimEnd('/')
            if (url.isEmpty()) return null
            return JEVConfig(url, if (jevDelaiMs > 0) jevDelaiMs else AISettingsRepository.JEV_DELAI_DEFAULT)
        }
}

class AISettingsRepository(context: Context) {
    private val dataStore = context.applicationContext.alphaNoteSettingsDataStore

    val settings: Flow<AISettings> = dataStore.data.map { prefs ->
        AISettings(
            enabled = prefs[ENABLED] ?: false,
            jevUrl = prefs[JEV_URL] ?: JEV_URL_DEFAULT,
            jevDelaiMs = prefs[JEV_DELAI] ?: JEV_DELAI_DEFAULT
        )
    }

    suspend fun current(): AISettings = settings.first()
    suspend fun setEnabled(enabled: Boolean) { dataStore.edit { it[ENABLED] = enabled } }
    suspend fun setJevUrl(url: String) { dataStore.edit { it[JEV_URL] = url.trim() } }
    suspend fun setJevDelaiMs(ms: Int) { dataStore.edit { it[JEV_DELAI] = ms.coerceIn(1000, 120_000) } }

    companion object {
        const val JEV_URL_DEFAULT = "http://192.168.3.169:8096"
        const val JEV_DELAI_DEFAULT = 20_000
        private val ENABLED = booleanPreferencesKey("jev_enabled")
        private val JEV_URL = stringPreferencesKey("jev_url")
        private val JEV_DELAI = intPreferencesKey("jev_delai_ms")
    }
}
