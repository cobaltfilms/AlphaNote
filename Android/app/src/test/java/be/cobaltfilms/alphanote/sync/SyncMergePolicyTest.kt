package be.cobaltfilms.alphanote.sync

import be.cobaltfilms.alphanote.model.Note
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SyncMergePolicyTest {
    @Test
    fun newerUpdatedAtWinsConflict() {
        val older = cloudNote(uuid = "note-1", content = "local", updatedAt = 1000)
        val newer = cloudNote(uuid = "note-1", content = "remote", updatedAt = 2000)

        assertEquals(newer, SyncMergePolicy.resolveConflict(older, newer))
    }

    @Test
    fun deletedNoteWinsWhenTimestampsTie() {
        val active = cloudNote(uuid = "note-1", isDeleted = false, updatedAt = 1000, deviceId = "b")
        val deleted = cloudNote(uuid = "note-1", isDeleted = true, updatedAt = 1000, deviceId = "b")

        assertEquals(deleted, SyncMergePolicy.resolveConflict(active, deleted))
    }

    @Test
    fun localMissingRemotesAreMerged() {
        val local = Note(uuid = "local-1", content = "local", updatedAt = 1000, createdAt = 1000)
        val remote = cloudNote(uuid = "remote-1", content = "remote", updatedAt = 1000)

        val merged = SyncMergePolicy.merge(mapOf(local.uuid to local), mapOf(remote.uuid to remote))

        assertEquals(setOf("local-1", "remote-1"), merged.keys)
    }

    @Test
    fun uploadWhenLocalWinsOrRemoteIsMissing() {
        val local = cloudNote(uuid = "note-1", content = "local", updatedAt = 2000)
        val remote = cloudNote(uuid = "note-1", content = "remote", updatedAt = 1000)

        assertTrue(SyncMergePolicy.shouldUploadLocal(local, remote, lastSyncedAt = 500))
        assertTrue(SyncMergePolicy.shouldUploadLocal(local, remote = null, lastSyncedAt = null))
        assertFalse(SyncMergePolicy.shouldUploadLocal(local, local, lastSyncedAt = 500))
    }

    @Test
    fun uuidIsExtractedFromRemoteJsonHref() {
        assertEquals("abc-123", SyncMergePolicy.uuidFromRemoteHref("/remote.php/dav/files/me/AlphaNote/notes/abc-123.json"))
        assertEquals(null, SyncMergePolicy.uuidFromRemoteHref("/remote.php/dav/files/me/AlphaNote/notes/"))
        assertEquals(null, SyncMergePolicy.uuidFromRemoteHref("readme.md"))
    }

    private fun cloudNote(
        uuid: String,
        content: String = "",
        updatedAt: Long = 1000,
        isDeleted: Boolean = false,
        deviceId: String = "android-test"
    ): CloudNoteDto {
        return CloudNoteDto(
            uuid = uuid,
            content = content,
            keyword = "",
            title = "",
            position = 0,
            isPinned = false,
            archived = false,
            isDeleted = isDeleted,
            deletedAt = if (isDeleted) updatedAt else null,
            createdAt = 1000,
            updatedAt = updatedAt,
            lastModifiedByDeviceId = deviceId
        )
    }
}
