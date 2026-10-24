package be.cobaltfilms.alphanote.sync

import android.content.Context
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.services.DeviceIdentity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.TimeUnit

enum class SyncRunTrigger {
    STARTUP,
    MANUAL,
    SCHEDULED
}

sealed class SyncRunState {
    object Idle : SyncRunState()
    object Syncing : SyncRunState()
    object TestingConnection : SyncRunState()
    object BackingUp : SyncRunState()
    object Restoring : SyncRunState()
    data class Success(val timestamp: Long) : SyncRunState()
    data class Error(val message: String) : SyncRunState()
}

class SyncConfigurationException(message: String) : Exception(message)

class SyncEngine(
    private val context: Context,
    private val repository: NoteRepository,
    private val settingsRepository: SyncSettingsRepository
) {
    private val appContext = context.applicationContext
    private val mutex = Mutex()
    private var schedulerJob: Job? = null

    private val _state = MutableStateFlow<SyncRunState>(SyncRunState.Idle)
    val state: StateFlow<SyncRunState> = _state.asStateFlow()

    private var localChangeJob: Job? = null
    private var engineScope: CoroutineScope? = null

    /** Une modification locale : synchro 30 s plus tard (regroupe les frappes). */
    fun notifyLocalChange() {
        val scope = engineScope ?: return
        localChangeJob?.cancel()
        localChangeJob = scope.launch {
            delay(LOCAL_CHANGE_DEBOUNCE_MS)
            if (settingsRepository.currentSettings().syncEnabled) runSync(SyncRunTrigger.SCHEDULED)
        }
    }

    fun start(scope: CoroutineScope) {
        engineScope = scope
        if (schedulerJob != null) return

        schedulerJob = scope.launch {
            settingsRepository.settings.collectLatest { settings ->
                if (!settings.syncEnabled) return@collectLatest
                runSync(SyncRunTrigger.STARTUP)
                while (isActive) {
                    delay(TimeUnit.MINUTES.toMillis(settings.syncIntervalMinutes.toLong()))
                    runSync(SyncRunTrigger.SCHEDULED)
                }
            }
        }
    }

    suspend fun runManualSync() {
        runSync(SyncRunTrigger.MANUAL)
        (state.value as? SyncRunState.Error)?.let { throw SyncConfigurationException(it.message) }
    }

    suspend fun testConnection() {
        mutex.withLock {
            _state.value = SyncRunState.TestingConnection
            try {
                makeClient().testConnection()
                _state.value = SyncRunState.Success(System.currentTimeMillis())
            } catch (error: Exception) {
                _state.value = SyncRunState.Error(error.message ?: "Connexion Nextcloud impossible.")
                throw error
            }
        }
    }

    suspend fun createBackup(): String {
        return mutex.withLock {
            _state.value = SyncRunState.BackingUp
            try {
                val now = System.currentTimeMillis()
                val backup = BackupDto(
                    deviceId = DeviceIdentity.currentDeviceId(appContext),
                    exportedAt = now,
                    notes = repository.getAllIncludingDeleted().map { CloudNoteDto.fromNote(it) }
                )
                val filename = makeClient().uploadBackup(backup)
                settingsRepository.markLastBackup(now)
                _state.value = SyncRunState.Success(now)
                filename
            } catch (error: Exception) {
                _state.value = SyncRunState.Error(error.message ?: "Backup Nextcloud impossible.")
                throw error
            }
        }
    }

    suspend fun restoreLatestBackup(): Int {
        return mutex.withLock {
            _state.value = SyncRunState.Restoring
            try {
                val now = System.currentTimeMillis()
                val backup = makeClient().fetchLatestBackup()
                backup.notes.forEach { dto ->
                    val existing = repository.getNoteByUuid(dto.uuid)
                    repository.saveFromSync(dto.toNote(existingId = existing?.id, lastSyncedAt = now))
                }
                settingsRepository.markLastRestore(now)
                _state.value = SyncRunState.Success(now)
                backup.notes.size
            } catch (error: Exception) {
                _state.value = SyncRunState.Error(error.message ?: "Restauration Nextcloud impossible.")
                throw error
            }
        }
    }

    private suspend fun runSync(trigger: SyncRunTrigger) {
        if (!mutex.tryLock()) return

        try {
            performSync(trigger)
        } finally {
            mutex.unlock()
        }
    }

    private suspend fun performSync(trigger: SyncRunTrigger) {
        when (trigger) {
            SyncRunTrigger.STARTUP,
            SyncRunTrigger.MANUAL,
            SyncRunTrigger.SCHEDULED -> Unit
        }
        _state.value = SyncRunState.Syncing

        try {
            val client = makeClient()
            client.ensureDirectories()
            client.fetchManifest()

            val remoteEntries = client.listNotes()
            val remoteByUUID = mutableMapOf<String, CloudNoteDto>()
            val remoteEtagsByUUID = mutableMapOf<String, String>()

            remoteEntries.forEach { entry ->
                val uuid = SyncMergePolicy.uuidFromRemoteHref(entry.href) ?: return@forEach
                val payload = client.fetchNote(uuid) ?: return@forEach
                remoteByUUID[uuid] = payload.dto
                payload.etag?.let { remoteEtagsByUUID[uuid] = it }
            }

            val localNotes = repository.getAllIncludingDeleted()
            val localByUUID = localNotes.associateBy { it.uuid }
            val merged = SyncMergePolicy.merge(localByUUID, remoteByUUID)
            val syncTimestamp = System.currentTimeMillis()

            merged.forEach { (uuid, dto) ->
                val existing = localByUUID[uuid]
                val existingDto = existing?.let { CloudNoteDto.fromNote(it) }
                if (existingDto != dto) {
                    repository.saveFromSync(dto.toNote(existingId = existing?.id, lastSyncedAt = syncTimestamp))
                }
            }

            val refreshedLocal = repository.getAllIncludingDeleted()
            val cutoff = syncTimestamp - TimeUnit.DAYS.toMillis(TOMBSTONE_RETENTION_DAYS)

            refreshedLocal.forEach { note ->
                val localDto = CloudNoteDto.fromNote(note)
                val remoteDto = remoteByUUID[note.uuid]

                if (note.isDeleted && note.deletedAt != null && note.deletedAt < cutoff) {
                    client.deleteNote(note.uuid)
                    return@forEach
                }

                if (SyncMergePolicy.shouldUploadLocal(localDto, remoteDto, note.lastSyncedAt)) {
                    val remoteEtag = remoteEtagsByUUID[note.uuid]
                    try {
                        client.uploadNote(localDto, remoteEtag)
                    } catch (error: NextcloudClientException.HttpStatus) {
                        if (error.code != 412) throw error
                        client.uploadNote(localDto, etag = null)
                    }
                    repository.markLastSynced(note.uuid, syncTimestamp)
                }
            }

            refreshedLocal
                .filter { it.isDeleted && it.deletedAt != null && it.deletedAt < cutoff }
                .forEach { client.deleteNote(it.uuid) }
            repository.purgeDeleted(cutoff)

            val finalNotes = repository.getAllIncludingDeleted()
            val manifest = ManifestDto(
                deviceId = DeviceIdentity.currentDeviceId(appContext),
                exportedAt = syncTimestamp,
                noteUUIDs = finalNotes.map { it.uuid }.sorted()
            )
            client.uploadManifest(manifest)
            settingsRepository.markLastSync(syncTimestamp)
            _state.value = SyncRunState.Success(syncTimestamp)
        } catch (error: Exception) {
            _state.value = SyncRunState.Error(error.message ?: "Synchronisation Nextcloud impossible.")
        }
    }

    private suspend fun makeClient(): NextcloudWebDavClient {
        val settings = settingsRepository.currentSettings()
        val serverUrl = settings.nextcloudServerUrl.trim()
        val username = settings.nextcloudUsername.trim()
        val password = settingsRepository.readPassword().orEmpty()

        if (serverUrl.isBlank()) throw SyncConfigurationException("URL du serveur Nextcloud manquante.")
        if (username.isBlank()) throw SyncConfigurationException("Identifiant Nextcloud manquant.")
        if (password.isBlank()) throw SyncConfigurationException("Mot de passe applicatif Nextcloud manquant.")

        return NextcloudWebDavClient(serverUrl, username, password)
    }

    private companion object {
        const val TOMBSTONE_RETENTION_DAYS = 30L
        const val LOCAL_CHANGE_DEBOUNCE_MS = 30_000L
    }
}
