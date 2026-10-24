package be.cobaltfilms.alphanote.sync

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import be.cobaltfilms.alphanote.data.alphaNoteSettingsDataStore
import be.cobaltfilms.alphanote.services.SecurePasswordStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first

data class SyncSettings(
    val syncEnabled: Boolean = false,
    val syncIntervalMinutes: Int = 5,
    val nextcloudServerUrl: String = "",
    val nextcloudUsername: String = "",
    val hasPassword: Boolean = false,
    val lastSyncAt: Long? = null,
    val lastBackupAt: Long? = null,
    val lastRestoreAt: Long? = null
) {
    val isConfigured: Boolean
        get() = nextcloudServerUrl.isNotBlank() && nextcloudUsername.isNotBlank() && hasPassword
}

class SyncSettingsRepository(context: Context) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.alphaNoteSettingsDataStore
    private val passwordStore = SecurePasswordStore(appContext)

    val settings: Flow<SyncSettings> = dataStore.data.map { prefs ->
        SyncSettings(
            syncEnabled = prefs[Keys.SYNC_ENABLED] ?: false,
            syncIntervalMinutes = (prefs[Keys.SYNC_INTERVAL_MINUTES] ?: 5).coerceAtLeast(1),
            nextcloudServerUrl = prefs[Keys.NEXTCLOUD_SERVER_URL] ?: "",
            nextcloudUsername = prefs[Keys.NEXTCLOUD_USERNAME] ?: "",
            hasPassword = prefs[Keys.NEXTCLOUD_PASSWORD_SAVED] ?: false,
            lastSyncAt = prefs[Keys.LAST_SYNC_AT],
            lastBackupAt = prefs[Keys.LAST_BACKUP_AT],
            lastRestoreAt = prefs[Keys.LAST_RESTORE_AT]
        )
    }

    suspend fun currentSettings(): SyncSettings = settings.first()

    suspend fun setSyncEnabled(enabled: Boolean) {
        dataStore.edit { it[Keys.SYNC_ENABLED] = enabled }
    }

    suspend fun setSyncIntervalMinutes(minutes: Int) {
        dataStore.edit { it[Keys.SYNC_INTERVAL_MINUTES] = minutes.coerceAtLeast(1) }
    }

    suspend fun setServerUrl(url: String) {
        dataStore.edit { it[Keys.NEXTCLOUD_SERVER_URL] = url.trim() }
    }

    suspend fun setUsername(username: String) {
        dataStore.edit { it[Keys.NEXTCLOUD_USERNAME] = username.trim() }
    }

    suspend fun savePassword(password: String) {
        passwordStore.savePassword(password)
        dataStore.edit { it[Keys.NEXTCLOUD_PASSWORD_SAVED] = password.isNotBlank() }
    }

    fun readPassword(): String? = passwordStore.readPassword()

    suspend fun markLastSync(timestamp: Long) {
        dataStore.edit { it[Keys.LAST_SYNC_AT] = timestamp }
    }

    suspend fun markLastBackup(timestamp: Long) {
        dataStore.edit { it[Keys.LAST_BACKUP_AT] = timestamp }
    }

    suspend fun markLastRestore(timestamp: Long) {
        dataStore.edit { it[Keys.LAST_RESTORE_AT] = timestamp }
    }

    private object Keys {
        val SYNC_ENABLED = booleanPreferencesKey("sync_enabled")
        val SYNC_INTERVAL_MINUTES = intPreferencesKey("sync_interval_minutes")
        val NEXTCLOUD_SERVER_URL = stringPreferencesKey("nextcloud_server_url")
        val NEXTCLOUD_USERNAME = stringPreferencesKey("nextcloud_username")
        val NEXTCLOUD_PASSWORD_SAVED = booleanPreferencesKey("nextcloud_password_saved")
        val LAST_SYNC_AT = longPreferencesKey("last_sync_at")
        val LAST_BACKUP_AT = longPreferencesKey("last_backup_at")
        val LAST_RESTORE_AT = longPreferencesKey("last_restore_at")
    }
}
