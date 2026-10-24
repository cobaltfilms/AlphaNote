package be.cobaltfilms.alphanote.sync

import be.cobaltfilms.alphanote.model.Note
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.format.DateTimeFormatter

data class CloudNoteDto(
    val schemaVersion: Int = 1,
    val uuid: String,
    val content: String,
    val keyword: String,
    val title: String,
    val position: Int,
    val isPinned: Boolean,
    val archived: Boolean,
    val isDeleted: Boolean,
    val deletedAt: Long?,
    val createdAt: Long,
    val updatedAt: Long,
    val lastModifiedByDeviceId: String
) {
    fun toNote(existingId: Long?, lastSyncedAt: Long?): Note {
        return Note(
            id = existingId ?: 0,
            uuid = uuid,
            content = content,
            keyword = keyword,
            title = title,
            position = position,
            isPinned = isPinned,
            archived = archived,
            isDeleted = isDeleted,
            deletedAt = deletedAt,
            lastSyncedAt = lastSyncedAt,
            lastModifiedByDeviceId = lastModifiedByDeviceId,
            createdAt = createdAt,
            updatedAt = updatedAt
        )
    }

    companion object {
        fun fromNote(note: Note): CloudNoteDto {
            return CloudNoteDto(
                uuid = note.uuid,
                content = note.content,
                keyword = note.keyword,
                title = note.title,
                position = note.position,
                isPinned = note.isPinned,
                archived = note.archived,
                isDeleted = note.isDeleted,
                deletedAt = note.deletedAt,
                createdAt = note.createdAt,
                updatedAt = note.updatedAt,
                lastModifiedByDeviceId = note.lastModifiedByDeviceId
            )
        }
    }
}

data class ManifestDto(
    val schemaVersion: Int = 1,
    val deviceId: String,
    val exportedAt: Long,
    val noteUUIDs: List<String>
)

data class BackupDto(
    val schemaVersion: Int = 1,
    val deviceId: String,
    val exportedAt: Long,
    val notes: List<CloudNoteDto>
)

object CloudJsonCoder {
    fun encodeNote(dto: CloudNoteDto): String = dto.toJson().toString()

    fun decodeNote(json: String): CloudNoteDto = JSONObject(json).toCloudNoteDto()

    fun encodeManifest(dto: ManifestDto): String {
        return JSONObject()
            .put("schemaVersion", dto.schemaVersion)
            .put("deviceId", dto.deviceId)
            .put("exportedAt", formatInstant(dto.exportedAt))
            .put("noteUUIDs", JSONArray(dto.noteUUIDs.sorted()))
            .toString()
    }

    fun decodeManifest(json: String): ManifestDto {
        val obj = JSONObject(json)
        val uuids = obj.optJSONArray("noteUUIDs") ?: JSONArray()
        return ManifestDto(
            schemaVersion = obj.optInt("schemaVersion", 1),
            deviceId = obj.optString("deviceId"),
            exportedAt = parseInstant(obj.optString("exportedAt")),
            noteUUIDs = (0 until uuids.length()).map { uuids.getString(it) }.sorted()
        )
    }

    fun encodeBackup(dto: BackupDto): String {
        val notes = JSONArray()
        dto.notes.sortedBy { it.uuid }.forEach { notes.put(it.toJson()) }
        return JSONObject()
            .put("schemaVersion", dto.schemaVersion)
            .put("deviceId", dto.deviceId)
            .put("exportedAt", formatInstant(dto.exportedAt))
            .put("notes", notes)
            .toString()
    }

    fun decodeBackup(json: String): BackupDto {
        val obj = JSONObject(json)
        val notes = obj.optJSONArray("notes") ?: JSONArray()
        return BackupDto(
            schemaVersion = obj.optInt("schemaVersion", 1),
            deviceId = obj.optString("deviceId"),
            exportedAt = parseInstant(obj.optString("exportedAt")),
            notes = (0 until notes.length()).map { notes.getJSONObject(it).toCloudNoteDto() }
        )
    }

    // Même format que macOS (CloudJSONCoder : « yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX »),
    // dont le décodeur exige toujours les millisecondes — ISO_INSTANT les omet
    // quand elles valent 0, ce qui cassait la lecture côté Mac.
    private val wireFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(java.time.ZoneOffset.UTC)

    fun formatInstant(timestamp: Long): String = wireFormatter.format(Instant.ofEpochMilli(timestamp))

    fun parseInstant(value: String): Long = Instant.parse(value).toEpochMilli()

    private fun CloudNoteDto.toJson(): JSONObject {
        return JSONObject()
            .put("schemaVersion", schemaVersion)
            .put("uuid", uuid)
            .put("content", content)
            .put("keyword", keyword)
            .put("title", title)
            .put("position", position)
            .put("isPinned", isPinned)
            .put("archived", archived)
            .put("isDeleted", isDeleted)
            .put("deletedAt", deletedAt?.let { formatInstant(it) } ?: JSONObject.NULL)
            .put("createdAt", formatInstant(createdAt))
            .put("updatedAt", formatInstant(updatedAt))
            .put("lastModifiedByDeviceId", lastModifiedByDeviceId)
    }

    private fun JSONObject.toCloudNoteDto(): CloudNoteDto {
        return CloudNoteDto(
            schemaVersion = optInt("schemaVersion", 1),
            uuid = getString("uuid"),
            content = optString("content"),
            keyword = optString("keyword"),
            title = optString("title"),
            position = optInt("position", 0),
            isPinned = optBoolean("isPinned", false),
            archived = optBoolean("archived", false),
            isDeleted = optBoolean("isDeleted", false),
            deletedAt = if (isNull("deletedAt")) null else parseInstant(getString("deletedAt")),
            createdAt = parseInstant(getString("createdAt")),
            updatedAt = parseInstant(getString("updatedAt")),
            lastModifiedByDeviceId = optString("lastModifiedByDeviceId")
        )
    }
}

object SyncMergePolicy {
    fun merge(
        localByUUID: Map<String, Note>,
        remoteByUUID: Map<String, CloudNoteDto>
    ): Map<String, CloudNoteDto> {
        val localDtos = localByUUID.mapValues { (_, note) -> CloudNoteDto.fromNote(note) }
        val allUUIDs = localDtos.keys + remoteByUUID.keys
        return allUUIDs.mapNotNull { uuid ->
            val local = localDtos[uuid]
            val remote = remoteByUUID[uuid]
            val merged = when {
                local != null && remote != null -> resolveConflict(local, remote)
                local != null -> local
                remote != null -> remote
                else -> null
            }
            merged?.let { uuid to it }
        }.toMap()
    }

    fun resolveConflict(lhs: CloudNoteDto, rhs: CloudNoteDto): CloudNoteDto {
        if (lhs.updatedAt > rhs.updatedAt) return lhs
        if (rhs.updatedAt > lhs.updatedAt) return rhs

        if (lhs.lastModifiedByDeviceId < rhs.lastModifiedByDeviceId) return lhs
        if (rhs.lastModifiedByDeviceId < lhs.lastModifiedByDeviceId) return rhs

        if (lhs.isDeleted != rhs.isDeleted) {
            return if (lhs.isDeleted) lhs else rhs
        }

        return lhs
    }

    fun shouldUploadLocal(local: CloudNoteDto, remote: CloudNoteDto?, lastSyncedAt: Long?): Boolean {
        if (remote == null) return true
        if (remote == local) return false // identique : rien à envoyer

        if (remote != local) {
            val winner = resolveConflict(local, remote)
            if (
                winner.uuid == local.uuid &&
                winner.updatedAt == local.updatedAt &&
                winner.lastModifiedByDeviceId == local.lastModifiedByDeviceId &&
                winner.isDeleted == local.isDeleted
            ) {
                return true
            }
        }

        return lastSyncedAt != null && local.updatedAt > lastSyncedAt
    }

    fun uuidFromRemoteHref(href: String): String? {
        val trimmed = href.trim()
        if (trimmed.endsWith("/")) return null
        val filename = trimmed.substringAfterLast("/")
        if (!filename.endsWith(".json")) return null
        return filename.removeSuffix(".json")
    }
}
