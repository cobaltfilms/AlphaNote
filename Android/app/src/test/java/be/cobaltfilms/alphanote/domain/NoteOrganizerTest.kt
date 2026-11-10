package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.ai.JEVClient
import be.cobaltfilms.alphanote.ai.JEVConfig
import be.cobaltfilms.alphanote.ai.JEVHttpError
import be.cobaltfilms.alphanote.ai.JEVTransport
import be.cobaltfilms.alphanote.ai.ThemeClassificationFeature
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset
import java.util.UUID

/**
 * Modes de rangement de la liste (forme, mois, tri à faire) et rangement par
 * JEV. Mêmes cas que OrganizerTests.swift côté Apple.
 */
class NoteOrganizerTest {

    private fun note(
        content: String, uuid: String = UUID.randomUUID().toString(), created: Long = 1_700_000_000,
        pinned: Boolean = false, title: String = ""
    ): Note = Note(
        uuid = uuid, content = content, keyword = Note(content = content).detectKeyword(), title = title,
        isPinned = pinned, createdAt = created * 1000
    )

    // ---- Forme ----

    @Test fun shapes() {
        assertEquals(NoteShape.TIMER, NoteOrganizer.shape(note("timer\ncountdown 5:00")))
        assertEquals(NoteShape.MATH, NoteOrganizer.shape(note("math\n2+2=")))
        assertEquals(NoteShape.LIST, NoteOrganizer.shape(note("list\npain\nlait")))
        assertEquals(NoteShape.TERMINAL, NoteOrganizer.shape(note("ls -la /var/log\ncd /etc/nginx")))
        assertEquals(NoteShape.LINK, NoteOrganizer.shape(note("À lire https://example.org/article")))
        assertEquals(NoteShape.LIST, NoteOrganizer.shape(note("pain\nlait\noeufs\nbeurre")))
        assertEquals(NoteShape.ONE_LINE, NoteOrganizer.shape(note("Rappeler Jeanne")))
        assertEquals(NoteShape.ONE_LINE, NoteOrganizer.shape(note("Rappeler Jeanne\nthème : Vie perso")))
        assertEquals(NoteShape.SHORT_TEXT, NoteOrganizer.shape(note("Cher Luc,\nmerci pour ta lettre, elle m'a fait très plaisir et je voulais te répondre.")))
        assertEquals(NoteShape.LONG_TEXT, NoteOrganizer.shape(note("Une phrase assez longue pour remplir. ".repeat(60))))
        assertEquals(NoteShape.VAULT, NoteOrganizer.shape(note("vault\nsecret")))
    }

    @Test fun meaningfulLinesDropHeaderThemeRemindersAndAttachments() {
        val content = "list: courses\npain\n\nrappel demain 9h\nthème : Cuisine\n![audio](att:a.m4a)"
        assertEquals(listOf("pain"), NoteOrganizer.meaningfulLines(note(content)))
    }

    // ---- Tri à faire ----

    @Test fun duplicatesKeepTheOldestNote() {
        val old = note("Recette de la dinde aux marrons, version de mamie", uuid = "old", created = 100)
        val copy = note("recette de la  DINDE aux marrons, version de mamie", uuid = "copy", created = 200)
        val other = note("Tout autre chose, sans aucun rapport avec la dinde", uuid = "other", created = 300)
        assertEquals(setOf("copy"), NoteOrganizer.duplicateUuids(listOf(copy, other, old)))
    }

    @Test fun triageReasons() {
        assertEquals(TriageReason.TIMER, NoteOrganizer.triageReason(note("timer\ncountdown 5:00"), emptySet()))
        assertEquals(TriageReason.LINK, NoteOrganizer.triageReason(note("https://example.org"), emptySet()))
        assertEquals(TriageReason.ONE_LINE, NoteOrganizer.triageReason(note("ZR701G87"), emptySet()))
        assertEquals(TriageReason.DUPLICATE, NoteOrganizer.triageReason(note("Un vrai texte", uuid = "d"), setOf("d")))
        // Épinglée, ou porteuse d'une note vocale : jamais proposée au tri.
        assertNull(NoteOrganizer.triageReason(note("ZR701G87", pinned = true), emptySet()))
        assertNull(NoteOrganizer.triageReason(note("Mémo\n![audio](att:a.m4a)"), emptySet()))
        assertNull(NoteOrganizer.triageReason(note("pain\nlait\noeufs\nbeurre"), emptySet()))
    }

    @Test fun triageSectionsEndWithTheRest() {
        val notes = listOf(note("https://example.org", uuid = "l"), note("pain\nlait\noeufs\nbeurre", uuid = "k"), note("timer", uuid = "t"))
        val sections = NoteOrganizer.sections(notes, NoteGrouping.TRIAGE, emptyMap())
        assertEquals(listOf("Minuteurs", "Liens seuls", NoteOrganizer.KEEP_TITLE), sections.map { it.title })
        assertEquals(listOf("k"), sections.last().noteUuids)
    }

    // ---- Sections ----

    @Test fun monthSectionsAreNewestFirst() {
        val notes = listOf(
            note("a", uuid = "a", created = 1_600_000_000), // septembre 2020
            note("b", uuid = "b", created = 1_700_000_000), // novembre 2023
            note("c", uuid = "c", created = 1_600_100_000),
        )
        val sections = NoteOrganizer.sections(notes, NoteGrouping.MONTH, emptyMap(), ZoneOffset.UTC)
        assertEquals(listOf("novembre 2023", "septembre 2020"), sections.map { it.title })
        assertEquals(listOf("a", "c"), sections[1].noteUuids)
    }

    @Test fun shapeSectionsFollowTheShapeOrder() {
        val notes = listOf(note("Rappeler Jeanne", uuid = "o"), note("ls -la /var/log\ncd /etc/nginx", uuid = "t"))
        assertEquals(listOf("Commandes et code", "Une seule ligne"), NoteOrganizer.sections(notes, NoteGrouping.SHAPE, emptyMap()).map { it.title })
        assertEquals(listOf(listOf("o", "t")), NoteOrganizer.sections(notes, NoteGrouping.RECENT, emptyMap()).map { it.noteUuids })
        assertEquals(listOf("Vie perso", NoteThemes.NONE), NoteOrganizer.sections(notes, NoteGrouping.THEME, mapOf("o" to "Vie perso")).map { it.title })
    }

    @Test fun groupingIsReadFromItsStoredName() {
        assertEquals(NoteGrouping.TRIAGE, NoteGrouping.fromRaw("triage"))
        assertEquals(NoteGrouping.RECENT, NoteGrouping.fromRaw(null))
        assertEquals(NoteGrouping.RECENT, NoteGrouping.fromRaw("inconnu"))
        assertEquals(listOf("Par date", "Par rayon", "Par forme", "Par mois de création", "Tri à faire"), NoteGrouping.entries.map { it.title })
    }

    // ---- Rangement par JEV ----

    /** Faux serveur : [reply] reçoit les fragments envoyés et rend une décision par fragment. */
    private fun fakeTransport(reply: (List<String>) -> List<Map<String, String>>) = JEVTransport { _, body, _, _ ->
        val sent = JSONObject(body).getJSONArray("contexts")
        val contexts = (0 until sent.length()).map(sent::getString)
        val results = JSONArray()
        reply(contexts).forEach { results.put(JSONObject().put("decision", JSONObject(it))) }
        JSONObject().put("results", results).toString()
    }

    private val config = JEVConfig("http://jev.test", 1000)

    @Test fun candidatesSkipVaultThemedAndEmptyNotes() {
        val notes = listOf(
            note("Une note à ranger", uuid = "a"),
            note("Déjà rangée\nthème : Cuisine", uuid = "b"),
            note("vault\nsecret", uuid = "c"),
            note("  \n", uuid = "d"),
            note("Supprimée", uuid = "e").copy(isDeleted = true),
        )
        assertEquals(listOf("a"), ThemeClassificationFeature.candidates(notes).map { it.uuid })
    }

    @Test fun fragmentIsTitleAndStartOfText() {
        val long = note("Titre\n" + "x".repeat(2000) + "\nthème : A\n![audio](att:a.m4a)", title = "Mon titre")
        val fragment = ThemeClassificationFeature.fragment(long)
        assertTrue(fragment.startsWith("Mon titre\nTitre\nxxx"))
        assertFalse(fragment.contains("thème"))
        assertFalse(fragment.contains("att:"))
        assertTrue(fragment.length <= "Mon titre\n".length + ThemeClassificationFeature.EXCERPT_LENGTH)
    }

    @Test fun schemaIsAcceptedByTheClient() {
        assertNull(JEVClient.verifierSchema(ThemeClassificationFeature.schema))
    }

    @Test fun shelvesUseTheLocalCatalogNames() {
        assertEquals(ThemeSorter.catalog.map { it.name }.toSet(), ThemeClassificationFeature.shelves.mapNotNull { it.theme }.toSet())
    }

    @Test fun classifyMapsShelvesAndLeavesTheRestUnsorted() = runBlocking {
        val notes = (0 until 10).map { note("Note numéro $it", uuid = "n$it") }
        val transport = fakeTransport { contexts ->
            contexts.map { text ->
                when {
                    text.endsWith("0") -> mapOf("rayon" to "cuisine")
                    text.endsWith("1") -> mapOf("rayon" to "fourre_tout")
                    text.endsWith("2") -> mapOf("rayon" to "inconnu")
                    else -> mapOf("rayon" to "informatique")
                }
            }
        }
        val progress = mutableListOf<Pair<Int, Int>>()
        val outcome = ThemeClassificationFeature.classify(notes, config, transport) { done, total -> progress.add(done to total) }
        assertEquals("Cuisine", outcome.themes["n0"])
        assertEquals("Informatique", outcome.themes["n3"])
        assertNull(outcome.themes["n1"])
        assertEquals(1, outcome.unsorted)
        assertEquals(1, outcome.failed)
        assertEquals(8, outcome.themes.size)
        assertNull(outcome.error)
        assertEquals(listOf(8 to 10, 10 to 10), progress)
    }

    @Test fun serverErrorStopsAndKeepsWhatWasDecided() = runBlocking {
        val notes = (0 until 12).map { note("Note numéro $it", uuid = "n$it") }
        var calls = 0
        val transport = fakeTransport { contexts ->
            if (++calls > 1) throw JEVHttpError(500)
            contexts.map { mapOf("rayon" to "cuisine") }
        }
        val outcome = ThemeClassificationFeature.classify(notes, config, transport)
        assertEquals(ThemeClassificationFeature.BATCH_SIZE, outcome.themes.size)
        assertEquals(12 - ThemeClassificationFeature.BATCH_SIZE, outcome.failed)
        assertNotNull(outcome.error)
    }
}
