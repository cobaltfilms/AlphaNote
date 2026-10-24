package be.cobaltfilms.alphanote.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

enum class ThemeMode(val raw: String, val label: String) {
    SYSTEM("system", "Système"), LIGHT("light", "Clair"), DARK("dark", "Sombre");

    companion object {
        fun fromRaw(raw: String?): ThemeMode = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

data class AppSettings(
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val fontSize: Float = 16f,
    val listCheckTrigger: String = "/x",
    val autoCleanup: Boolean = true,
    val confirmDelete: Boolean = true,
    val appcastUrl: String = AppSettingsRepository.APPCAST_URL_DEFAULT
)

/** Réglages généraux (miroir de Réglages › Général / Apparence sur macOS). */
class AppSettingsRepository(context: Context) {
    private val dataStore = context.applicationContext.alphaNoteSettingsDataStore

    val settings: Flow<AppSettings> = dataStore.data.map { prefs ->
        AppSettings(
            theme = ThemeMode.fromRaw(prefs[THEME]),
            fontSize = (prefs[FONT_SIZE] ?: 16f).coerceIn(12f, 26f),
            listCheckTrigger = (prefs[LIST_TRIGGER] ?: "/x").ifBlank { "/x" },
            autoCleanup = prefs[AUTO_CLEANUP] ?: true,
            confirmDelete = prefs[CONFIRM_DELETE] ?: true,
            appcastUrl = prefs[APPCAST_URL]?.takeUnless { it == LEGACY_APPCAST_URL } ?: APPCAST_URL_DEFAULT
        )
    }

    suspend fun setTheme(mode: ThemeMode) { dataStore.edit { it[THEME] = mode.raw } }
    suspend fun setFontSize(size: Float) { dataStore.edit { it[FONT_SIZE] = size.coerceIn(12f, 26f) } }
    suspend fun setListCheckTrigger(trigger: String) { dataStore.edit { it[LIST_TRIGGER] = trigger.trim().ifBlank { "/x" } } }
    suspend fun setAutoCleanup(enabled: Boolean) { dataStore.edit { it[AUTO_CLEANUP] = enabled } }
    suspend fun setConfirmDelete(enabled: Boolean) { dataStore.edit { it[CONFIRM_DELETE] = enabled } }
    suspend fun setAppcastUrl(url: String) { dataStore.edit { it[APPCAST_URL] = url.trim() } }

    companion object {
        /** Dépôt public de releases : Gitea exige une connexion, même pour un dépôt public. */
        const val APPCAST_URL_DEFAULT = "https://raw.githubusercontent.com/cobaltfilms/AlphaNote/main/appcast-android.json"
        private const val LEGACY_APPCAST_URL = "https://git.cobaltfilms.be/paul/AlphaNote/raw/branch/main/appcast-android.json"
        private val THEME = stringPreferencesKey("theme")
        private val FONT_SIZE = floatPreferencesKey("font_size")
        private val LIST_TRIGGER = stringPreferencesKey("list_check_trigger")
        private val AUTO_CLEANUP = booleanPreferencesKey("auto_cleanup")
        private val CONFIRM_DELETE = booleanPreferencesKey("confirm_delete")
        private val APPCAST_URL = stringPreferencesKey("appcast_url")
    }
}
