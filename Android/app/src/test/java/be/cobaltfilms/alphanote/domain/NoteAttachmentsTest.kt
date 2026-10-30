package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class NoteAttachmentsTest {

    @Test fun markdownRoundTripsThroughNames() {
        val content = "Recette\n" + NoteAttachments.markdown("a1b2.jpg") + "\nÉtapes"
        assertEquals(listOf("a1b2.jpg"), NoteAttachments.names(content))
    }

    @Test fun namesKeepOrderOfAppearance() {
        val content = "${NoteAttachments.markdown("first.jpg")}\ntexte\n${NoteAttachments.markdown("second.jpg")}"
        assertEquals(listOf("first.jpg", "second.jpg"), NoteAttachments.names(content))
    }

    @Test fun ordinaryMarkdownLinksAreNotImages() {
        assertEquals(emptyList<String>(), NoteAttachments.names("[lien](https://example.com/att:x.jpg)"))
    }

    @Test fun shareTextDropsImageLinesOnly() {
        val content = "liste\n${NoteAttachments.markdown("x.jpg")}\n- pain\n"
        assertEquals("liste\n- pain", NoteAttachments.textWithoutImages(content))
    }
}
