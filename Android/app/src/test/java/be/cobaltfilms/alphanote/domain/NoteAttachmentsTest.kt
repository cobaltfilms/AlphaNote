package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    // ---- Notes vocales ----

    @Test fun audioReferencesAreSeparatedFromImages() {
        val content = "Texte\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        assertTrue(NoteAttachments.isAudio("b.m4a"))
        assertTrue(NoteAttachments.isAudio("B.WAV"))
        assertFalse(NoteAttachments.isAudio("a.jpg"))
        assertEquals(listOf("a.jpg"), NoteAttachments.imageNames(content))
        assertEquals(listOf("b.m4a"), NoteAttachments.audioNames(content))
        assertEquals("![audio](att:b.m4a)", NoteAttachments.markdown("b.m4a"))
        assertEquals("![image](att:a.jpg)", NoteAttachments.markdown("a.jpg"))
        assertTrue(NoteAttachments.isAudioLine("![audio](att:b.m4a)"))
        assertFalse(NoteAttachments.isAudioLine("![image](att:a.jpg)"))
        assertTrue(NoteAttachments.newAudioName().endsWith(".m4a"))
    }

    /** L'éditeur cache toutes les pièces jointes ; l'audio revient avec le bon alt. */
    @Test fun editorRoundTripKeepsAudioReferences() {
        val content = "Texte\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        assertEquals("Texte", NoteAttachments.visibleText(content))
        assertEquals(content, NoteAttachments.withImages(NoteAttachments.visibleText(content), content))
    }

    @Test fun addingVoiceNote() {
        assertEquals("Bonjour\n![audio](att:a.m4a)", NoteAttachments.addingVoiceNote("", "a.m4a", " Bonjour "))
        assertEquals(
            "Idée\n\nAppeler le client\nthème : Travail\n![image](att:i.jpg)\n![audio](att:a.m4a)",
            NoteAttachments.addingVoiceNote("Idée\nthème : Travail\n![image](att:i.jpg)", "a.m4a", "Appeler le client")
        )
        // Transcription vide : seule la référence est ajoutée.
        assertEquals("Idée\n![audio](att:a.m4a)", NoteAttachments.addingVoiceNote("Idée", "a.m4a", ""))
    }

    @Test fun removingReferenceKeepsTranscript() {
        val content = "Idée\n\nAppeler le client\n![audio](att:a.m4a)\n![audio](att:b.m4a)"
        assertEquals("Idée\n\nAppeler le client\n![audio](att:b.m4a)", NoteAttachments.removingReference("a.m4a", content))
    }
}
