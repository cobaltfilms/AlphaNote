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

    /** Toutes les notes non supprimées : épinglées d'abord, puis les plus récemment créées */
    @Query("""
        SELECT * FROM note 
        WHERE isDeleted = 0 AND archived = 0
        ORDER BY isPinned DESC, createdAt DESC, id DESC
    """)
    fun observeActiveNotes(): Flow<List<Note>>

    /** Récupération directe (hors Flow) pour les opérations ponctuelles */
    @Query("""
        SELECT * FROM note 
        WHERE isDeleted = 0 AND archived = 0
        ORDER BY isPinned DESC, createdAt DESC, id DESC
    """)
    suspend fun getActiveNotes(): List<Note>

    @Query("SELECT * FROM note ORDER BY position ASC")
    suspend fun getAllIncludingDeleted(): List<Note>

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
        SET isDeleted = 1, deletedAt = :now, updatedAt = :now, lastModifiedByDeviceId = :deviceId
        WHERE id = :id
    """)
    suspend fun softDelete(id: Long, deviceId: String, now: Long = System.currentTimeMillis())

    @Query("""
        UPDATE note
        SET archived = :archived, updatedAt = :now, lastModifiedByDeviceId = :deviceId
        WHERE id = :id
    """)
    suspend fun setArchived(id: Long, archived: Boolean, deviceId: String, now: Long = System.currentTimeMillis())

    @Query("""
        DELETE FROM note 
        WHERE isDeleted = 1 AND deletedAt IS NOT NULL AND deletedAt < :cutoff
    """)
    suspend fun purgeDeleted(cutoff: Long)

    @Query("""
        UPDATE note 
        SET isDeleted = 1, deletedAt = :now, updatedAt = :now, lastModifiedByDeviceId = :deviceId
        WHERE TRIM(content) = '' AND isDeleted = 0
    """)
    suspend fun softDeleteEmpty(deviceId: String, now: Long = System.currentTimeMillis())

    @Query("""
        UPDATE note
        SET isPinned = :pinned, updatedAt = :now, lastModifiedByDeviceId = :deviceId
        WHERE id = :id
    """)
    suspend fun setPinned(id: Long, pinned: Boolean, deviceId: String, now: Long = System.currentTimeMillis())

    @Query("SELECT * FROM note WHERE isDeleted = 0 ORDER BY archived ASC, isPinned DESC, createdAt DESC, id DESC")
    suspend fun getAllNotDeleted(): List<Note>

    @Query("SELECT COALESCE(MAX(position), -1) + 1 FROM note WHERE isDeleted = 0")
    suspend fun nextPosition(): Int

    /** Met à jour le timestamp de dernière synchronisation */
    @Query("UPDATE note SET lastSyncedAt = :timestamp WHERE uuid = :uuid")
    suspend fun markLastSynced(uuid: String, timestamp: Long)

    /** Récupère les notes par leur UUID (pour la synchro) */
    @Query("SELECT * FROM note WHERE uuid IN (:uuids)")
    suspend fun getByUuids(uuids: List<String>): List<Note>
}
