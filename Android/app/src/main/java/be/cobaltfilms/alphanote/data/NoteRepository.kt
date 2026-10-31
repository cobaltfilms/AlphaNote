package be.cobaltfilms.alphanote.data

import android.content.Context
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.services.DeviceIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * Repository — couche d'abstraction entre le ViewModel et Room.
 * Toute écriture locale estampille updatedAt et lastModifiedByDeviceId
 * (la synchro s'en sert pour trancher les conflits).
 */
class NoteRepository(context: Context) {

    private val appContext = context.applicationContext
    private val dao: NoteDao = AppDatabase.getInstance(appContext).noteDao()
    private val deviceId: String get() = DeviceIdentity.currentDeviceId(appContext)

    val activeNotes: Flow<List<Note>> = dao.observeActiveNotes()
    val archivedNotes: Flow<List<Note>> = dao.observeArchivedNotes()
    val activeNoteCount: Flow<Int> = dao.observeActiveCount()

    suspend fun getAllNotes(): List<Note> = dao.getActiveNotes()
    suspend fun getAllNotDeleted(): List<Note> = dao.getAllNotDeleted()
    suspend fun getAllIncludingDeleted(): List<Note> = dao.getAllIncludingDeleted()
    suspend fun getNoteById(id: Long): Note? = dao.getById(id)

    /** Vide le journal WAL : l'ancienne version en clair d'une note qui vient
     *  d'entrer au coffre ne reste pas dans les fichiers. */
    suspend fun purgeJournal() = withContext(Dispatchers.IO) {
        AppDatabase.getInstance(appContext).openHelper.writableDatabase
            .query("PRAGMA wal_checkpoint(TRUNCATE)").use { it.moveToFirst() }
    }
    suspend fun getNoteByUuid(uuid: String): Note? = dao.getByUuid(uuid)

    suspend fun createNote(content: String = "", keyword: String = "", title: String = ""): Note {
        val now = System.currentTimeMillis()
        val probe = Note(content = content)
        val note = Note(
            uuid = UUID.randomUUID().toString().lowercase(),
            content = content,
            keyword = keyword.ifEmpty { probe.detectKeyword() },
            title = title,
            position = dao.nextPosition(),
            lastModifiedByDeviceId = deviceId,
            createdAt = now,
            updatedAt = now
        )
        val id = dao.insert(note)
        return note.copy(id = id)
    }

    /** Met à jour une note ; le mot-clé est redétecté depuis la première ligne. */
    suspend fun updateNote(note: Note): Note {
        val updated = note.copy(
            keyword = note.detectKeyword(),
            lastModifiedByDeviceId = deviceId,
            updatedAt = System.currentTimeMillis()
        )
        dao.update(updated)
        return updated
    }

    suspend fun deleteNote(note: Note) { if (note.id > 0) dao.softDelete(note.id, deviceId) }
    suspend fun archiveNote(note: Note) { if (note.id > 0) dao.setArchived(note.id, true, deviceId) }
    suspend fun unarchiveNote(note: Note) { if (note.id > 0) dao.setArchived(note.id, false, deviceId) }
    suspend fun setPinned(note: Note, pinned: Boolean) { if (note.id > 0) dao.setPinned(note.id, pinned, deviceId) }

    suspend fun duplicateNote(note: Note): Note = createNote(content = note.content, keyword = note.keyword, title = note.title)

    suspend fun renameNote(note: Note, title: String): Note = updateNote(note.copy(title = title.trim()))

    /** Sauvegarde depuis la synchronisation (upsert basé sur uuid). */
    suspend fun saveFromSync(note: Note) {
        val existing = dao.getByUuid(note.uuid)
        if (existing != null) {
            dao.update(existing.copy(
                content = note.content, keyword = note.keyword, title = note.title, position = note.position,
                isPinned = note.isPinned, archived = note.archived, isDeleted = note.isDeleted, deletedAt = note.deletedAt,
                lastSyncedAt = note.lastSyncedAt, lastModifiedByDeviceId = note.lastModifiedByDeviceId,
                createdAt = note.createdAt, updatedAt = note.updatedAt
            ))
        } else {
            dao.insert(note.copy(id = 0))
        }
    }

    suspend fun markLastSynced(uuid: String, timestamp: Long = System.currentTimeMillis()) = dao.markLastSynced(uuid, timestamp)
    suspend fun purgeDeleted(cutoff: Long) = dao.purgeDeleted(cutoff)
    suspend fun deleteEmpty() = dao.softDeleteEmpty(deviceId)
}
