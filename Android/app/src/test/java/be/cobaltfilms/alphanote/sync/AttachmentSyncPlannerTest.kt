package be.cobaltfilms.alphanote.sync

import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.sync.AttachmentSyncPlanner.Item
import be.cobaltfilms.alphanote.sync.AttachmentSyncPlanner.RemoteEntry
import be.cobaltfilms.alphanote.vault.VaultEnvelope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Plan de synchro des pièces jointes : logique pure, sans réseau ni disque. */
class AttachmentSyncPlannerTest {
    private fun note(uuid: String, content: String, deleted: Boolean = false, keyword: String = "") =
        Note(uuid = uuid, content = content, keyword = keyword, isDeleted = deleted)

    // ---- Références ----

    @Test
    fun referencesKeepLiveNotesOnly() {
        val notes = listOf(
            note("n1", "Courses\n![audio](att:a.m4a)\n![image](att:b.jpg)"),
            note("n2", "Corbeille\n![audio](att:c.m4a)", deleted = true),
            note("n3", "vault: Secret\n![audio](att:d.m4a)", keyword = VaultEnvelope.KEYWORD),
            note("n4", "Sans pièce jointe")
        )
        assertEquals(mapOf("n1" to listOf("a.m4a", "b.jpg")), AttachmentSyncPlanner.references(notes))
    }

    @Test
    fun referencesDropDuplicatesAndUnsafeNames() {
        val notes = listOf(note("n1", "![audio](att:a.m4a)\n![audio](att:a.m4a)\n![image](att:..)\n![image](att:.cache)\n![image](att:.)"))
        assertEquals(mapOf("n1" to listOf("a.m4a")), AttachmentSyncPlanner.references(notes))
    }

    @Test
    fun referencesSkipUnsafeNoteUuid() {
        val notes = listOf(note("../autre", "![audio](att:a.m4a)"), note("", "![audio](att:b.m4a)"))
        assertTrue(AttachmentSyncPlanner.references(notes).isEmpty())
    }

    // ---- Noms ----

    @Test
    fun safeNames() {
        assertTrue(AttachmentSyncPlanner.isSafeName("3f2a-9c.m4a"))
        assertTrue(AttachmentSyncPlanner.isSafeName("photo_1.JPG"))
        for (bad in listOf("", ".", "..", ".part", "a/b.m4a", "a\\b", "a b.m4a", "é.m4a", "a.m4a\n")) {
            assertFalse(AttachmentSyncPlanner.isSafeName(bad), bad)
        }
    }

    @Test
    fun safeNoteUuids() {
        assertTrue(AttachmentSyncPlanner.isSafeNoteUuid("0b6e1d3c-1111-4222-8333-444455556666"))
        for (bad in listOf("", ".", "..", "a/b", "a.b", "a b")) {
            assertFalse(AttachmentSyncPlanner.isSafeNoteUuid(bad), bad)
        }
    }

    // ---- Plan ----

    @Test
    fun planUploadsLocalOnlyAndDownloadsRemoteOnly() {
        val plan = AttachmentSyncPlanner.plan(
            references = mapOf("n1" to listOf("here.m4a", "there.m4a", "both.jpg", "nowhere.m4a")),
            local = mapOf("n1" to setOf("here.m4a", "both.jpg")),
            remote = mapOf("n1" to setOf("there.m4a", "both.jpg"))
        )
        assertEquals(listOf(Item("n1", "here.m4a")), plan.uploads)
        assertEquals(listOf(Item("n1", "there.m4a")), plan.downloads)
    }

    @Test
    fun planIgnoresUnreferencedFiles() {
        // Fichier retiré du texte, ou d'une note absente des références
        // (supprimée, sécurisée) : ni envoyé, ni téléchargé, ni supprimé.
        val plan = AttachmentSyncPlanner.plan(
            references = mapOf("n1" to listOf("a.m4a")),
            local = mapOf("n1" to setOf("a.m4a", "orphelin.m4a"), "n2" to setOf("x.m4a")),
            remote = mapOf("n1" to setOf("a.m4a", "ancien.jpg"), "n3" to setOf("y.m4a"))
        )
        assertTrue(plan.isEmpty)
    }

    @Test
    fun planWithNoRemoteFolderUploadsEverythingLocal() {
        val plan = AttachmentSyncPlanner.plan(
            references = mapOf("n2" to listOf("b.m4a"), "n1" to listOf("a.m4a", "manquant.m4a")),
            local = mapOf("n1" to setOf("a.m4a"), "n2" to setOf("b.m4a")),
            remote = emptyMap()
        )
        assertEquals(listOf(Item("n1", "a.m4a"), Item("n2", "b.m4a")), plan.uploads)
        assertTrue(plan.downloads.isEmpty())
    }

    @Test
    fun planNeverEscapesTheNoteFolder() {
        val plan = AttachmentSyncPlanner.plan(
            references = mapOf(
                "n1" to listOf("..", ".", ".secret", "a/b.m4a", "ok.m4a"),
                "../n2" to listOf("x.m4a"),
                "" to listOf("y.m4a")
            ),
            local = mapOf("n1" to setOf("..", "."), "../n2" to setOf("x.m4a")),
            remote = mapOf("n1" to setOf(".secret", "a/b.m4a", "ok.m4a"), "" to setOf("y.m4a"))
        )
        assertTrue(plan.uploads.isEmpty())
        assertEquals(listOf(Item("n1", "ok.m4a")), plan.downloads)
    }

    @Test
    fun planFromNotesEndToEnd() {
        val notes = listOf(
            note("n1", "Mémo\n![audio](att:a.m4a)"),
            note("n2", "Supprimée\n![audio](att:b.m4a)", deleted = true),
            note("n3", "vault\n![audio](att:c.m4a)", keyword = VaultEnvelope.KEYWORD)
        )
        val plan = AttachmentSyncPlanner.plan(
            references = AttachmentSyncPlanner.references(notes),
            local = mapOf("n2" to setOf("b.m4a"), "n3" to setOf("c.m4a")),
            remote = mapOf("n1" to setOf("a.m4a"), "n2" to emptySet(), "n3" to emptySet())
        )
        assertTrue(plan.uploads.isEmpty())
        assertEquals(listOf(Item("n1", "a.m4a")), plan.downloads)
    }

    // ---- Liste WebDAV ----

    @Test
    fun remoteEntryParsing() {
        val base = "/remote.php/dav/files/paul/AlphaNote/attachments/"
        assertNull(AttachmentSyncPlanner.remoteEntry(base))
        assertEquals(RemoteEntry("n1", null), AttachmentSyncPlanner.remoteEntry(base + "n1/"))
        assertEquals(RemoteEntry("n1", "a.m4a"), AttachmentSyncPlanner.remoteEntry(base + "n1/a.m4a"))
        assertEquals(RemoteEntry("n1", "a.m4a"), AttachmentSyncPlanner.remoteEntry("https://cloud.example.org" + base + "n1/a.m4a"))
        // Fichier posé directement dans `attachments`, sous-dossier, nom douteux, autre dossier.
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "perdu.m4a"))
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "n1/sous/a.m4a"))
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "n1/sous/"))
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "n1/a%20b.m4a"))
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "n1/a+b.m4a"))
        assertNull(AttachmentSyncPlanner.remoteEntry(base + "n1/%2E%2E"))
        assertNull(AttachmentSyncPlanner.remoteEntry("/remote.php/dav/files/paul/AlphaNote/notes/n1.json"))
    }
}
