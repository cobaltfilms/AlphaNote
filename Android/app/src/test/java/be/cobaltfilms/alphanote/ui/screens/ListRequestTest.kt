package be.cobaltfilms.alphanote.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Test

/** Demandes de liste sans IA : mêmes cas que ListRequestTests.swift (macOS). */
class ListRequestTest {
    @Test
    fun destinationIsNotAnItem() {
        assertEquals(listOf("du café", "du beurre", "des pommes"),
            NoteViewModel.listItems("ajoute du café, du beurre et des pommes à mes courses"))
        assertEquals(listOf("de l'huile d'olive"), NoteViewModel.listItems("ajoute de l'huile d'olive dans la liste"))
    }

    @Test
    fun plainEnumerationIsUntouched() {
        assertEquals(listOf("tomates", "pâtes", "huile"), NoteViewModel.listItems("courses : tomates, pâtes, huile"))
    }
}
