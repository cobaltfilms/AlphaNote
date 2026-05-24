package be.cobaltfilms.alphanote.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.flow.Flow

/**
 * Data Access Object pour les notes.
 * Expose des Flow pour l'observation réactive des changements.
 */
@Dao
interface NoteDao {

    /** Toutes les notes non supprimées, triées par épinglé puis position */
    @Query("""
        SELECT * FROM note 
        WHERE isDeleted = 0 AND archived = 0
        ORDER BY isPinned DESC, position ASC
    """)
    fun observeActiveNotes(): Flow<List<Note>>

    /** Récupération directe (hors Flow) pour les opérations ponctuelles */
    @Query("""
        SELECT * FROM note 
        WHERE isDeleted = 0 AND archived = 0
        ORDER BY isPinned DESC, position ASC
    """)
    suspend fun getActiveNotes(): List<Note>

    @Query("""
        SELECT * FROM note
        WHERE isDeleted = 0 AND archived = 1
        ORDER BY updatedAt DESC
    """)
    fun observeArchivedNotes(): Flow<List<Note>>

    @Query("SELECT * FROM note WHERE id = :id")
    suspend fun getById(id: Long): Note?

    @Query("SELECT * FROM note WHERE uuid = :uuid")
    suspend fun getByUuid(uuid: String): Note?

    @Query("SELECT COUNT(*) FROM note")
    suspend fun count(): Int

    @Query("SELECT COUNT(*) FROM note WHERE isDeleted = 0")
    suspend fun countNotDeleted(): Int

    /** Nombre de notes non supprimées */
    @Query("SELECT COUNT(*) FROM note WHERE isDeleted = 0 AND archived = 0")
    fun observeActiveCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: Note): Long

    @Update
    suspend fun update(note: Note)

    @Query("""
        UPDATE note 
        SET isDeleted = 1, deletedAt = :now, updatedAt = :now 
        WHERE id = :id
    """)
    suspend fun softDelete(id: Long, now: Long = System.currentTimeMillis())

    @Query("""
        UPDATE note
        SET archived = :archived, updatedAt = :now
        WHERE id = :id
    """)
    suspend fun setArchived(id: Long, archived: Boolean, now: Long = System.currentTimeMillis())

    @Query("""
        DELETE FROM note 
        WHERE isDeleted = 1 AND deletedAt IS NOT NULL AND deletedAt < :cutoff
    """)
    suspend fun purgeDeleted(cutoff: Long)

    @Query("""
        UPDATE note 
        SET isDeleted = 1, deletedAt = :now, updatedAt = :now 
        WHERE TRIM(content) = '' AND isDeleted = 0
    """)
    suspend fun softDeleteEmpty(now: Long = System.currentTimeMillis())

    /** Met à jour le timestamp de dernière synchronisation */
    @Query("UPDATE note SET lastSyncedAt = :timestamp WHERE uuid = :uuid")
    suspend fun markLastSynced(uuid: String, timestamp: Long)

    /** Récupère les notes par leur UUID (pour la synchro) */
    @Query("SELECT * FROM note WHERE uuid IN (:uuids)")
    suspend fun getByUuids(uuids: List<String>): List<Note>
}
