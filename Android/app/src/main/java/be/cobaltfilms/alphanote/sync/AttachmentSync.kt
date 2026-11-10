package be.cobaltfilms.alphanote.sync

import android.content.Context
import android.util.Log
import be.cobaltfilms.alphanote.domain.NoteAttachments
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLDecoder

/**
 * Synchro Nextcloud des pièces jointes (images et notes vocales), même logique
 * que la version Apple (`Sync/AttachmentSync.swift`).
 *
 * Sur le serveur : `AlphaNote/attachments/<uuid de la note>/<nom>`, à côté de
 * `AlphaNote/notes/`. Les fichiers sont immuables (leur nom est un UUID) : un
 * fichier présent des deux côtés n'est jamais comparé ni renvoyé, il n'y a
 * donc pas de conflit. Rien n'est jamais supprimé en local parce qu'un fichier
 * manque sur le serveur.
 */
object AttachmentSyncPlanner {
    data class Item(val noteUuid: String, val name: String)

    data class Plan(val uploads: List<Item> = emptyList(), val downloads: List<Item> = emptyList()) {
        val isEmpty: Boolean get() = uploads.isEmpty() && downloads.isEmpty()
    }

    /** Entrée d'une liste WebDAV sous `attachments/` : un dossier de note ([name] null) ou un fichier. */
    data class RemoteEntry(val noteUuid: String, val name: String?)

    const val FOLDER_NAME = "attachments"
    private const val REMOTE_MARKER = "/AlphaNote/$FOLDER_NAME/"
    private val safeName = Regex("[A-Za-z0-9._-]+")
    private val safeUuid = Regex("[A-Za-z0-9_-]+")

    /**
     * Nom de fichier sûr : les mêmes caractères que dans une référence
     * `att:<nom>`, sans point initial — ni « . » ni « .. », pour ne jamais lire
     * ni écrire hors du dossier de la note.
     */
    fun isSafeName(name: String): Boolean = !name.startsWith(".") && name.length <= 200 && safeName.matches(name)

    /** UUID de note utilisable comme nom de dossier. */
    fun isSafeNoteUuid(uuid: String): Boolean = uuid.length <= 100 && safeUuid.matches(uuid)

    /**
     * Pièces jointes à synchroniser : références `att:` des notes vivantes et
     * non sécurisées, par UUID de note, sans doublon, dans l'ordre du texte.
     */
    fun references(notes: List<Note>): Map<String, List<String>> {
        val result = mutableMapOf<String, List<String>>()
        for (note in notes) {
            if (note.isDeleted || note.isVault || !isSafeNoteUuid(note.uuid)) continue
            val names = NoteAttachments.names(note.content).filter(::isSafeName).distinct()
            if (names.isNotEmpty()) result[note.uuid] = names
        }
        return result
    }

    /**
     * Le plan : fichier local présent et absent du serveur → envoi ; fichier
     * local absent et présent sur le serveur → téléchargement. Absent des deux
     * côtés (l'appareil d'origine n'a pas encore synchronisé) : rien.
     */
    fun plan(
        references: Map<String, List<String>>,
        local: Map<String, Set<String>>,
        remote: Map<String, Set<String>>
    ): Plan {
        val uploads = mutableListOf<Item>()
        val downloads = mutableListOf<Item>()
        for (uuid in references.keys.sorted()) {
            if (!isSafeNoteUuid(uuid)) continue
            for (name in references[uuid].orEmpty().filter(::isSafeName).distinct()) {
                val here = local[uuid]?.contains(name) == true
                val there = remote[uuid]?.contains(name) == true
                if (here && !there) uploads += Item(uuid, name)
                if (!here && there) downloads += Item(uuid, name)
            }
        }
        return Plan(uploads, downloads)
    }

    /**
     * Lit un `href` de PROPFIND sous `…/AlphaNote/attachments/`. Null pour le
     * dossier lui-même, un chemin plus profond ou un nom qui n'est pas sûr.
     */
    fun remoteEntry(href: String): RemoteEntry? {
        val trimmed = href.trim()
        val withoutHost = if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            val slash = trimmed.indexOf('/', trimmed.indexOf("://") + 3)
            if (slash < 0) return null else trimmed.substring(slash)
        } else trimmed
        // « + » n'est pas une espace dans un chemin : on le protège avant de décoder.
        val path = runCatching { URLDecoder.decode(withoutHost.replace("+", "%2B"), "UTF-8") }.getOrNull() ?: return null
        val marker = path.indexOf(REMOTE_MARKER)
        if (marker < 0) return null
        val isDirectory = trimmed.endsWith("/")
        val parts = path.substring(marker + REMOTE_MARKER.length).split("/").filter { it.isNotEmpty() }
        return when {
            parts.size == 1 && isDirectory && isSafeNoteUuid(parts[0]) -> RemoteEntry(parts[0], null)
            parts.size == 2 && !isDirectory && isSafeNoteUuid(parts[0]) && isSafeName(parts[1]) -> RemoteEntry(parts[0], parts[1])
            else -> null
        }
    }
}

/** Bilan d'une passe : ce qui a circulé, et ce qui a échoué. */
data class AttachmentSyncOutcome(val uploaded: Int = 0, val downloaded: Int = 0, val failed: Int = 0)

/**
 * Exécution du plan contre Nextcloud. Une erreur ne remonte jamais (sauf
 * l'annulation de la coroutine) : elle est comptée et journalisée, la synchro
 * des notes n'en dépend pas.
 */
internal class AttachmentSync(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("alphanote_sync_attachments", Context.MODE_PRIVATE)

    /** Contenu connu d'un dossier distant, valable tant que son ETag ne change pas. */
    private data class Listing(val etag: String, val names: List<String>)

    suspend fun run(client: NextcloudWebDavClient, notes: List<Note>, scope: String): AttachmentSyncOutcome {
        var uploaded = 0
        var downloaded = 0
        var failed = 0
        var networkDown = false
        fun outcome() = AttachmentSyncOutcome(uploaded, downloaded, failed)

        val references = AttachmentSyncPlanner.references(notes)
        if (references.isEmpty()) return outcome()

        // Un fichier vide (enregistrement raté) compte comme absent : il n'est pas envoyé.
        val local = withContext(Dispatchers.IO) {
            references.mapValues { (uuid, names) ->
                names.filter { NoteAttachments.file(appContext, uuid, it).length() > 0 }.toSet()
            }
        }.toMutableMap()

        // Dossiers de notes présents sur le serveur (null : `attachments` n'existe pas encore).
        val folders = mutableMapOf<String, String?>()
        var rootExists = true
        try {
            val entries = client.listAttachmentFolders()
            if (entries == null) rootExists = false
            entries?.forEach { entry ->
                val parsed = AttachmentSyncPlanner.remoteEntry(entry.href) ?: return@forEach
                if (parsed.name == null) folders[parsed.noteUuid] = entry.etag
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w(TAG, "Liste des pièces jointes impossible", error)
            return AttachmentSyncOutcome(failed = 1)
        }

        val known = loadListings(scope)
        val listings = mutableMapOf<String, Listing>()
        val remote = mutableMapOf<String, Set<String>>()
        for (uuid in references.keys.sorted()) {
            if (uuid !in folders) continue // pas de dossier : rien sur le serveur
            val etag = folders[uuid]
            val cached = known[uuid]
            if (etag != null && cached != null && cached.etag == etag) {
                remote[uuid] = cached.names.toSet()
                listings[uuid] = cached
                continue
            }
            try {
                val names = client.listAttachments(uuid).mapNotNull { entry ->
                    AttachmentSyncPlanner.remoteEntry(entry.href)?.takeIf { it.noteUuid == uuid }?.name
                }
                remote[uuid] = names.toSet()
                if (etag != null) listings[uuid] = Listing(etag, names.sorted())
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                // Contenu inconnu : on ne touche pas à cette note pendant cette passe.
                Log.w(TAG, "Liste du dossier $uuid impossible", error)
                failed += 1
                remote[uuid] = references[uuid].orEmpty().toSet()
                local[uuid] = references[uuid].orEmpty().toSet()
                if (error.isNetworkFailure()) {
                    // Réseau coupé : on s'arrête là, la prochaine synchro reprendra.
                    saveListings(scope, listings)
                    return outcome()
                }
            }
        }
        saveListings(scope, listings)

        val plan = AttachmentSyncPlanner.plan(references, local, remote)
        val readyFolders = folders.keys.toMutableSet()

        for (item in plan.downloads) {
            try {
                val target = NoteAttachments.file(appContext, item.noteUuid, item.name)
                if (client.downloadAttachment(item.noteUuid, item.name, target)) downloaded += 1 else failed += 1
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                Log.w(TAG, "Téléchargement de ${item.noteUuid}/${item.name} impossible", error)
                failed += 1
                if (error.isNetworkFailure()) { networkDown = true; break }
            }
        }
        // Les rangées « Enregistrée sur un autre appareil » et les vignettes relisent leur fichier.
        if (downloaded > 0) NoteAttachments.revision.value += 1
        // Réseau coupé : on s'arrête là, la prochaine synchro reprendra.
        if (networkDown) return outcome()

        for (item in plan.uploads) {
            try {
                if (!rootExists) {
                    client.ensureAttachmentsFolder(null)
                    rootExists = true
                }
                if (readyFolders.add(item.noteUuid)) client.ensureAttachmentsFolder(item.noteUuid)
                client.uploadAttachment(item.noteUuid, item.name, NoteAttachments.file(appContext, item.noteUuid, item.name))
                uploaded += 1
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                readyFolders.remove(item.noteUuid)
                Log.w(TAG, "Envoi de ${item.noteUuid}/${item.name} impossible", error)
                failed += 1
                if (error.isNetworkFailure()) break
            }
        }
        return outcome()
    }

    private fun Throwable.isNetworkFailure(): Boolean = this is IOException || cause is IOException

    private fun loadListings(scope: String): Map<String, Listing> {
        val raw = prefs.getString(scope, null) ?: return emptyMap()
        return runCatching {
            val obj = JSONObject(raw)
            obj.keys().asSequence().associateWith { uuid ->
                val entry = obj.getJSONObject(uuid)
                val names = entry.getJSONArray("names")
                Listing(entry.getString("etag"), (0 until names.length()).map(names::getString))
            }
        }.getOrDefault(emptyMap())
    }

    private fun saveListings(scope: String, listings: Map<String, Listing>) {
        val obj = JSONObject()
        listings.forEach { (uuid, listing) ->
            obj.put(uuid, JSONObject().put("etag", listing.etag).put("names", JSONArray(listing.names)))
        }
        prefs.edit().putString(scope, obj.toString()).apply()
    }

    private companion object {
        const val TAG = "AttachmentSync"
    }
}
