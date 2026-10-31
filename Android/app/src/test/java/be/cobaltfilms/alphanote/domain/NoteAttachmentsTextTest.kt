package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Test

/** L'éditeur cache les lignes d'images ; le contenu stocké les garde en fin de note. */
class NoteAttachmentsTextTest {
    private val img = NoteAttachments.markdown("a1.jpg")
    private val img2 = NoteAttachments.markdown("b2.jpg")

    @Test
    fun editorNeverShowsReferences() {
        assertEquals("Inspiration", NoteAttachments.visibleText("Inspiration\n$img"))
        assertEquals("A\nB", NoteAttachments.visibleText("A\n$img\nB"))
    }

    /** Texte tapé → stocké → réaffiché : identique, saut de ligne final compris. */
    @Test
    fun roundTripIsExact() {
        for (typed in listOf("", "A", "A\n", "A\n\n", "list: Courses\n- pain\n")) {
            val stored = NoteAttachments.withImages(typed, "x\n$img\n$img2")
            assertEquals(typed, NoteAttachments.visibleText(stored))
            assertEquals(listOf("a1.jpg", "b2.jpg"), NoteAttachments.names(stored))
        }
    }

    @Test
    fun noImagesLeavesTextUntouched() {
        assertEquals("A\n", NoteAttachments.withImages("A\n", "A\n"))
    }
}
