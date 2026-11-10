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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import org.json.JSONObject
import java.io.IOException
import java.net.UnknownHostException

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
    private var retryJob: Job? = null
    private val etagStore = ETagStore(context.applicationContext)
    private val attachmentSync = AttachmentSync(context.applicationContext)
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

        // Seuls « activée » et l'intervalle relancent la boucle : l'heure de
        // dernière synchro change aussi ces réglages, et relançait une synchro
        // complète juste après chaque synchro (en annulant celle en cours).
        schedulerJob = scope.launch {
            settingsRepository.settings
                .map { it.syncEnabled to it.syncIntervalMinutes }
                .distinctUntilChanged()
                .collectLatest { (enabled, interval) ->
                    if (!enabled) return@collectLatest
                    runSync(SyncRunTrigger.STARTUP)
                    while (isActive) {
                        delay(TimeUnit.MINUTES.toMillis(interval.toLong()))
                        runSync(SyncRunTrigger.SCHEDULED)
                    }
                }
        }
    }

    /** L'app revient au premier plan : on rattrape tout de suite ce qui a changé. */
    fun onForeground() {
        val scope = engineScope ?: return
        scope.launch { if (settingsRepository.currentSettings().syncEnabled) runSync(SyncRunTrigger.SCHEDULED) }
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

    /**
     * Même logique que macOS (SyncEngine.swift), en plus robuste aux coupures :
     *  · seules les notes dont l'ETag a changé sont téléchargées (en parallèle) ;
     *  · chaque note reçue est fusionnée et enregistrée aussitôt, et son ETag
     *    retenu : une synchro interrompue (écran éteint, réseau coupé en
     *    arrière-plan) ne repart pas de zéro ;
     *  · une note illisible est ignorée et signalée, sans bloquer les autres ;
     *  · une coupure réseau arrête la synchro et en relance une 30 s plus tard.
     */
    private suspend fun performSync(trigger: SyncRunTrigger) {
        when (trigger) {
            SyncRunTrigger.STARTUP,
            SyncRunTrigger.MANUAL,
            SyncRunTrigger.SCHEDULED -> Unit
        }
        _state.value = SyncRunState.Syncing

        try {
            val settings = settingsRepository.currentSettings()
            val client = makeClient()
            val etagScope = "${settings.nextcloudUsername.trim()}@${settings.nextcloudServerUrl.trim()}"
            val knownETags = etagStore.load(etagScope)
            var skipped = 0

            client.ensureDirectories()

            val remoteEntries = client.listNotes()
            val localByUUID = repository.getAllIncludingDeleted().associateBy { it.uuid }.toMutableMap()
            val remoteByUUID = mutableMapOf<String, CloudNoteDto>()
            val remoteEtagsByUUID = mutableMapOf<String, String>()
            val seenRemoteUUIDs = mutableSetOf<String>()
            val toFetch = mutableListOf<String>()

            remoteEntries.forEach { entry ->
                val uuid = SyncMergePolicy.uuidFromRemoteHref(entry.href) ?: return@forEach
                seenRemoteUUIDs += uuid
                val local = localByUUID[uuid]
                if (entry.etag != null && knownETags[uuid] == entry.etag && local?.lastSyncedAt != null) {
                    // Inchangée sur le serveur depuis notre dernière synchro.
                    remoteByUUID[uuid] = CloudNoteDto.fromNote(local)
                    remoteEtagsByUUID[uuid] = entry.etag
                } else {
                    toFetch += uuid
                }
            }

            val syncTimestamp = System.currentTimeMillis()
            for (chunk in toFetch.chunked(DOWNLOAD_PARALLELISM)) {
                val payloads = coroutineScope {
                    chunk.map { uuid -> async { uuid to runCatching { client.fetchNote(uuid) } } }.awaitAll()
                }
                for ((uuid, result) in payloads) {
                    val payload = result.getOrElse { error ->
                        if (error.isNetworkFailure()) throw error
                        skipped += 1
                        null
                    } ?: continue
                    remoteByUUID[uuid] = payload.dto
                    payload.etag?.let { remoteEtagsByUUID[uuid] = it }

                    val existing = localByUUID[uuid]
                    val existingDto = existing?.let { CloudNoteDto.fromNote(it) }
                    val merged = existingDto?.let { SyncMergePolicy.resolveConflict(it, payload.dto) } ?: payload.dto
                    if (merged != existingDto) {
                        val saved = merged.toNote(existingId = existing?.id, lastSyncedAt = syncTimestamp)
                        repository.saveFromSync(saved)
                        localByUUID[uuid] = repository.getNoteByUuid(uuid) ?: saved
                    } else if (existing != null && existing.lastSyncedAt == null && existingDto == payload.dto) {
                        // Déjà identique sur le serveur : simplement notée comme synchronisée.
                        repository.markLastSynced(uuid, syncTimestamp)
                        localByUUID[uuid] = existing.copy(lastSyncedAt = syncTimestamp)
                    }
                    payload.etag?.let { knownETags[uuid] = it }
                }
                etagStore.save(etagScope, knownETags) // progression gardée si on est coupé
            }

            val refreshedLocal = repository.getAllIncludingDeleted()
            val cutoff = syncTimestamp - TimeUnit.DAYS.toMillis(TOMBSTONE_RETENTION_DAYS)

            for (note in refreshedLocal) {
                if (note.isDeleted && note.deletedAt != null && note.deletedAt < cutoff) {
                    client.deleteNote(note.uuid)
                    knownETags.remove(note.uuid)
                    // Ses pièces jointes partent avec elle ; un échec ici ne bloque rien.
                    try {
                        client.deleteAttachments(note.uuid)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                    }
                    continue
                }
                val localDto = CloudNoteDto.fromNote(note)
                val remoteDto = remoteByUUID[note.uuid]
                if (!SyncMergePolicy.shouldUploadLocal(localDto, remoteDto, note.lastSyncedAt)) continue

                try {
                    val newEtag = try {
                        client.uploadNote(localDto, remoteEtagsByUUID[note.uuid])
                    } catch (error: NextcloudClientException.HttpStatus) {
                        if (error.code != 412) throw error
                        client.uploadNote(localDto, etag = null)
                    }
                    repository.markLastSynced(note.uuid, syncTimestamp)
                    if (newEtag != null) knownETags[note.uuid] = newEtag else knownETags.remove(note.uuid)
                } catch (error: Exception) {
                    if (error is CancellationException || error.isNetworkFailure()) throw error
                    skipped += 1
                }
            }

            repository.purgeDeleted(cutoff)
            knownETags.keys.retainAll { it in seenRemoteUUIDs || localByUUID[it]?.lastSyncedAt != null }
            etagStore.save(etagScope, knownETags)

            val finalNotes = repository.getAllIncludingDeleted()
            client.uploadManifest(
                ManifestDto(
                    deviceId = DeviceIdentity.currentDeviceId(appContext),
                    exportedAt = syncTimestamp,
                    noteUUIDs = finalNotes.map { it.uuid }.sorted()
                )
            )
            settingsRepository.markLastSync(syncTimestamp)
            // Les notes reçues portent peut-être des rappels : on reprogramme les alarmes.
            be.cobaltfilms.alphanote.reminders.ReminderScheduler.rescheduleAll(appContext, repository)

            // Pièces jointes, après les notes : un échec ici est compté, jamais
            // propagé — la synchro des notes est déjà faite.
            val attachments = attachmentSync.run(client, finalNotes, etagScope)
            _state.value = when {
                skipped > 0 -> SyncRunState.Error("Synchronisation faite, mais $skipped note(s) illisible(s) ou refusée(s) par le serveur ont été ignorées.")
                attachments.failed > 0 -> SyncRunState.Error("Notes synchronisées, mais ${attachments.failed} pièce(s) jointe(s) n'ont pas pu être envoyées ou reçues. Nouvel essai à la prochaine synchro.")
                else -> SyncRunState.Success(syncTimestamp)
            }
        } catch (error: CancellationException) {
            _state.value = SyncRunState.Idle
            throw error
        } catch (error: Exception) {
            _state.value = SyncRunState.Error(describe(error))
            if (error.isNetworkFailure()) scheduleRetry()
        }
    }

    /** Coupure réseau : nouvel essai dans 30 s (tant que l'app tourne). */
    private fun scheduleRetry() {
        val scope = engineScope ?: return
        retryJob?.cancel()
        retryJob = scope.launch {
            delay(NETWORK_RETRY_MS)
            if (settingsRepository.currentSettings().syncEnabled) runSync(SyncRunTrigger.SCHEDULED)
        }
    }

    private fun describe(error: Exception): String = when {
        error is UnknownHostException || error.cause is UnknownHostException ->
            "Serveur injoignable (pas de réseau, ou l'app était en arrière-plan). Nouvel essai dans 30 s."
        error.isNetworkFailure() -> "Connexion au serveur interrompue. Nouvel essai dans 30 s."
        else -> error.message ?: "Synchronisation Nextcloud impossible."
    }

    private fun Throwable.isNetworkFailure(): Boolean =
        this is IOException || cause is IOException

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
        const val NETWORK_RETRY_MS = 30_000L
        const val DOWNLOAD_PARALLELISM = 8
    }
}

/** ETag connu de chaque note distante, par compte (miroir de syncRemoteETagsV1 sur macOS). */
internal class ETagStore(context: Context) {
    private val prefs = context.getSharedPreferences("alphanote_sync_etags", Context.MODE_PRIVATE)

    fun load(scope: String): MutableMap<String, String> {
        val raw = prefs.getString(scope, null) ?: return mutableMapOf()
        return runCatching {
            val obj = JSONObject(raw)
            obj.keys().asSequence().associateWith { obj.getString(it) }.toMutableMap()
        }.getOrDefault(mutableMapOf())
    }

    fun save(scope: String, etags: Map<String, String>) {
        prefs.edit().putString(scope, JSONObject(etags).toString()).apply()
    }
}
