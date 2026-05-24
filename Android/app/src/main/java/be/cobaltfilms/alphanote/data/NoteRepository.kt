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

    /** Flux réactif des notes archivées */
    val archivedNotes: Flow<List<Note>> = dao.observeArchivedNotes()

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
        val resolvedKeyword = if (keyword.isNotEmpty()) keyword else inferKeywordFromContent(content)
        val note = Note(
            uuid = UUID.randomUUID().toString().lowercase(),
            content = content,
            keyword = resolvedKeyword,
            title = title,
            position = dao.countNotDeleted(),
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        val id = dao.insert(note)
        return note.copy(id = id)
    }

    /**
     * Met à jour une note existante.
     * Le keyword est automatiquement détecté et mis à jour.
     */
    suspend fun updateNote(note: Note): Note {
        val updatedKeyword = if (note.keyword.isNotBlank()) note.keyword else inferKeywordFromContent(note.content)
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

    suspend fun archiveNote(note: Note) {
        if (note.id > 0) {
            dao.setArchived(note.id, true)
        }
    }

    suspend fun unarchiveNote(note: Note) {
        if (note.id > 0) {
            dao.setArchived(note.id, false)
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

    private fun inferKeywordFromContent(content: String): String {
        val explicit = Note(content = content).detectKeyword()
        if (explicit.isNotBlank()) return explicit

        val lines = content.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return ""
        if (lines.any { it.endsWith("=") }) return "math"
        if (lines.any { Regex("\\d\\s*[+\\-*/^]\\s*\\d").containsMatchIn(it) }) return "math"

        return ""
    }
}
