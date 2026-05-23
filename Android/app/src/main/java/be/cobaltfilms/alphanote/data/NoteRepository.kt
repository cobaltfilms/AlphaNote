package be.cobaltfilms.alphanote.data

import android.content.Context
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Repository — couche d'abstraction entre les ViewModels et Room.
 * Pattern single-source-of-truth.
 */
class NoteRepository(context: Context) {

    private val dao: NoteDao = AppDatabase.getInstance(context).noteDao()

    /** Flux réactif de toutes les notes actives */
    val activeNotes: Flow<List<Note>> = dao.observeActiveNotes()

    /** Flux du nombre de notes actives */
    val activeNoteCount: Flow<Int> = dao.observeActiveCount()

    suspend fun getAllNotes(): List<Note> = dao.getActiveNotes()

    suspend fun getNoteById(id: Long): Note? = dao.getById(id)

    suspend fun getNoteByUuid(uuid: String): Note? = dao.getByUuid(uuid)

    /**
     * Crée une nouvelle note avec un UUID frais.
     * Détecte automatiquement le keyword à partir du contenu.
     */
    suspend fun createNote(content: String = "", keyword: String = "", title: String = ""): Note {
        val note = Note(
            uuid = UUID.randomUUID().toString().lowercase(),
            content = content,
            keyword = keyword.ifEmpty { content.let { Note(content = content).let { n -> n.detectKeyword() } } },
            title = title,
            position = dao.count().toInt(),
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        val correctedKeyword = if (keyword.isEmpty()) note.detectKeyword() else keyword
        val corrected = note.copy(keyword = correctedKeyword)
        val id = dao.insert(corrected)
        return corrected.copy(id = id)
    }

    /**
     * Met à jour une note existante.
     * Le keyword est automatiquement détecté et mis à jour.
     */
    suspend fun updateNote(note: Note): Note {
        val updatedKeyword = note.detectKeyword()
        val updated = note.copy(
            keyword = updatedKeyword,
            updatedAt = System.currentTimeMillis()
        )
        dao.update(updated)
        return updated
    }

    /** Suppression logicielle (soft delete) */
    suspend fun deleteNote(note: Note) {
        if (note.id > 0) {
            dao.softDelete(note.id)
        }
    }

    /** Sauvegarde depuis la synchronisation (upsert basé sur uuid) */
    suspend fun saveFromSync(note: Note) {
        val existing = dao.getByUuid(note.uuid)
        if (existing != null) {
            val merged = existing.copy(
                content = note.content,
                keyword = note.keyword,
                title = note.title,
                position = note.position,
                isPinned = note.isPinned,
                archived = note.archived,
                isDeleted = note.isDeleted,
                deletedAt = note.deletedAt,
                lastSyncedAt = note.lastSyncedAt,
                aiSummary = note.aiSummary.ifEmpty { existing.aiSummary },
                aiLastProcessedAt = note.aiLastProcessedAt ?: existing.aiLastProcessedAt,
                createdAt = note.createdAt,
                updatedAt = note.updatedAt
            )
            dao.update(merged)
        } else {
            dao.insert(note.copy(id = 0))
        }
    }

    suspend fun markLastSynced(uuid: String, timestamp: Long = System.currentTimeMillis()) {
        dao.markLastSynced(uuid, timestamp)
    }

    suspend fun purgeDeleted(cutoff: Long) {
        dao.purgeDeleted(cutoff)
    }

    suspend fun deleteEmpty() {
        dao.softDeleteEmpty()
    }
}
