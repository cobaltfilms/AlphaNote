package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeywordDetectorTest {

    @Test
    fun detectKeyword_readsFirstLineKeyword() {
        val keyword = KeywordDetector.detectKeyword("math\n2+2=")
        assertEquals("math", keyword)
    }

    @Test
    fun detectKeyword_readsKeywordPrefix() {
        val keyword = KeywordDetector.detectKeyword("list: Courses\npain")
        assertEquals("list", keyword)
    }

    @Test
    fun classifyIntent_detectsMathExpression() {
        val intent = KeywordDetector.classifyIntent("calcule 20% de 50", noteKeyword = null)
        assertEquals(KeywordDetector.NoteIntent.MATH, intent)
    }

    @Test
    fun classifyIntent_detectsListRequest() {
        val intent = KeywordDetector.classifyIntent("fais une liste de courses", noteKeyword = null)
        assertEquals(KeywordDetector.NoteIntent.LIST, intent)
    }

    @Test
    fun isWebResearchRequest_detectsUrl() {
        assertTrue(KeywordDetector.isWebResearchRequest("analyse https://example.com"))
    }
}
