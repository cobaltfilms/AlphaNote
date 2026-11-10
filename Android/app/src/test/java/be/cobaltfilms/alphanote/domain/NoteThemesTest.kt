package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.ui.screens.preview
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Thèmes : ligne « thème : … » et classement local. Mêmes cas que ThemesAndVoiceTests.swift. */
class NoteThemesTest {

    // ---- Ligne de thème ----

    @Test fun explicitThemeIsReadFromItsLine() {
        assertEquals("Recettes", NoteThemes.explicit("Tarte\nthème : Recettes"))
        assertEquals("voyage", NoteThemes.explicit("Theme: voyage\nBillets"))
        assertEquals("Deux mots", NoteThemes.explicit("x\nTHÈME :  Deux   mots "))
        assertNull(NoteThemes.explicit("Le thème du film est sombre"))
        assertNull(NoteThemes.explicit("thème :   "))
    }

    @Test fun lastThemeLineWins() {
        assertEquals("B", NoteThemes.explicit("thème : A\ntexte\nthème : B"))
    }

    @Test fun nameIsBoundedInLength() {
        assertEquals(NoteThemes.MAX_LENGTH, NoteThemes.normalized("a".repeat(60)).length)
    }

    @Test fun settingThemeReplacesAndRemoves() {
        assertEquals("Réunion\nthème : Travail", NoteThemes.settingTheme("Travail", "Réunion"))
        assertEquals("Réunion\nthème : Perso", NoteThemes.settingTheme("Perso", "Réunion\nthème : Travail"))
        assertEquals("Réunion", NoteThemes.settingTheme(null, "Réunion\nthème : Travail"))
        assertEquals("Réunion", NoteThemes.settingTheme("  ", "Réunion\nthème : Travail"))
    }

    @Test fun themeLineStaysBeforeTrailingAttachments() {
        val content = "Repérage\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        assertEquals(
            "Repérage\nthème : Tournage\n![image](att:a.jpg)\n![audio](att:b.m4a)",
            NoteThemes.settingTheme("Tournage", content)
        )
    }

    @Test fun themeKeyIgnoresCaseAndAccents() {
        assertEquals(NoteThemes.key("ecoles"), NoteThemes.key("Écoles"))
        assertNotEquals(NoteThemes.key("Travail"), NoteThemes.key("Voyage"))
    }

    @Test fun sectionsAreAlphabeticalWithNoThemeLast() {
        val sections = NoteThemes.sections(
            listOf("1", "2", "3", "4", "5"),
            mapOf("1" to "Voyage", "3" to "Recettes", "4" to "voyage", "5" to "Écoles")
        )
        assertEquals(listOf("Écoles", "Recettes", "Voyage", NoteThemes.NONE), sections.map { it.theme })
        assertEquals(listOf("1", "4"), sections[2].noteUuids)
        assertEquals(listOf("2"), sections[3].noteUuids)
    }

    @Test fun distinctNamesKeepOneSpellingPerTheme() {
        assertEquals(listOf("Écoles", "Voyage"), NoteThemes.distinctNames(listOf("voyage", "Voyage", "Écoles")))
    }

    @Test fun previewHidesThemeLine() {
        val note = Note(content = "Tarte aux pommes\npommes, beurre\nthème : Recettes\n![audio](att:a.m4a)")
        assertEquals("pommes, beurre", preview(note))
    }

    // ---- Classement ----

    @Test fun tokensDropAccentsPluralsAndStopWords() {
        assertEquals(listOf("gateau", "huile", "olive"), ThemeSorter.tokens("Les gâteaux et l'huile d'olive"))
    }

    @Test fun catalogRecognisesCommonThemes() {
        assertEquals("Cuisine", ThemeSorter.catalogTheme("Recette gâteau", ""))
        assertEquals("Cuisine", ThemeSorter.catalogTheme("", "Recette gâteau\nau chocolat"))
        assertEquals("Cuisine", ThemeSorter.catalogTheme("", "list\npain\nfromage\nyaourt"))
        assertEquals("Vie perso", ThemeSorter.catalogTheme("", "Vol Bruxelles Lisbonne\nhôtel réservé, passeport à renouveler"))
        assertNull(ThemeSorter.catalogTheme("", "Rappeler Jeanne demain matin"))
    }

    @Test fun oneCatalogWordIsNotEnough() {
        assertNull(ThemeSorter.catalogTheme("", "IKEA"))
        assertNull(ThemeSorter.catalogTheme("", "Appeler la banque"))
        assertEquals("Argent & papiers", ThemeSorter.catalogTheme("", "Banque\nvirement du loyer"))
    }

    @Test fun explicitThemeIsKeptAndTeachesSimilarNotes() {
        val items = listOf(
            ThemeSorter.Item("a", "", "Repérage décor usine\ncomédiens à confirmer\nthème : Tournage Lyon", ""),
            ThemeSorter.Item("b", "", "Décor du hangar, repérage jeudi avec les comédiens\nthème : Tournage Lyon", ""),
            ThemeSorter.Item("c", "", "Repérage du second décor, comédiens prévenus", ""),
            ThemeSorter.Item("d", "", "Rappeler Jeanne demain matin", ""),
        )
        val themes = ThemeSorter.assign(items)
        assertEquals("Tournage Lyon", themes["a"])
        assertEquals("Tournage Lyon", themes["c"])
        assertNull(themes["d"])
    }

    @Test fun terminalDumpGoesToTech() {
        val log = "Jul 20 18:47:36 host kernel: [ 12.345] usb 1-1: new device\n$ sudo dmesg --follow\necho 1 > /sys/bus/pci/rescan"
        assertTrue(ThemeSorter.looksLikeCode(log))
        assertFalse(ThemeSorter.looksLikeCode("Cher Luc,\nmerci pour ta lettre (et pour le livre).\nÀ bientôt"))
        val themes = ThemeSorter.assign(listOf(ThemeSorter.Item("a", "", "ls -la /var/log\ncd /etc/nginx", "")))
        assertEquals("Informatique", themes["a"])
    }

    @Test fun codeNoteFallsBackToTechTheme() {
        val themes = ThemeSorter.assign(listOf(ThemeSorter.Item("a", "", "code\nfoo(bar)", "code")))
        assertEquals("Informatique", themes["a"])
        // Sans aucun mot connu ni allure de code : le mode « code » suffit.
        assertEquals("Informatique", ThemeSorter.assign(listOf(ThemeSorter.Item("b", "", "code\nabracadabra", "code")))["b"])
    }

    @Test fun assignIsDeterministic() {
        val items = (0 until 40).map { index ->
            ThemeSorter.Item("$index", "", if (index % 2 == 0) "Recette tarte $index\nfarine beurre" else "Facture banque $index\nvirement", "")
        }
        assertEquals(ThemeSorter.assign(items), ThemeSorter.assign(items))
        assertEquals("Cuisine", ThemeSorter.assign(items)["0"])
        assertEquals("Argent & papiers", ThemeSorter.assign(items)["1"])
    }
}
