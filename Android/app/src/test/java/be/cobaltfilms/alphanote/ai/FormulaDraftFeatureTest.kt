package be.cobaltfilms.alphanote.ai

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FormulaDraftFeatureTest {
    private val config = JEVConfig("http://test", 1000)

    private fun chatCompletion(content: String) = JSONObject()
        .put("model", "/models/Qwen3-8B-Q4_K_M.gguf")
        .put("choices", JSONArray().put(JSONObject().put("message", JSONObject().put("role", "assistant").put("content", content))))
        .toString()

    @Test
    fun parseLinesStripsThinkAndFences() {
        val outcome = FormulaDraftFeature.parseLines("<think>\n</think>\n```json\n{\"lignes\": [\"pi * 3^2 =\"]}\n```")
        assertEquals(JEVOutcome.Ok(listOf("pi * 3^2 =")), outcome)
    }

    @Test
    fun validFormulaWithVariablesIsAccepted() {
        assertNull(FormulaDraftFeature.validate(listOf("taux: 0.03 / 12", "mois: 20 * 12", "200000 * taux / (1 - (1 + taux)^(-mois)) =")))
    }

    @Test
    fun namedResultLineIsAccepted() {
        assertNull(FormulaDraftFeature.validate(listOf("rayon: 3", "aire: pi * rayon^2 =")))
    }

    @Test
    fun unknownWordIsRejected() {
        // L'évaluateur ignorerait « rayon » et rendrait 9 : on refuse.
        assertNotNull(FormulaDraftFeature.validate(listOf("pi * rayon^2 =")))
    }

    @Test
    fun missingResultLineAndReservedNameAreRejected() {
        assertNotNull(FormulaDraftFeature.validate(listOf("r: 3")))
        assertNotNull(FormulaDraftFeature.validate(listOf("sqrt: 3", "sqrt * 2 =")))
    }

    @Test
    fun draftHappyPathKeepsModelName() = runBlocking {
        val transport = JEVTransport { _, _, _ -> chatCompletion("""{"lignes": ["pi * 3^2 ="]}""") }
        val outcome = FormulaDraftFeature.draft("aire d'un cercle de rayon 3", config, transport)
        assertEquals(JEVOutcome.Ok(FormulaDraftFeature.Draft(listOf("pi * 3^2 ="), "Qwen3-8B-Q4_K_M.gguf")), outcome)
    }

    @Test
    fun draftWithUnknownWordIsAFrankError() = runBlocking {
        val transport = JEVTransport { _, _, _ -> chatCompletion("""{"lignes": ["pi * rayon^2 ="]}""") }
        val outcome = FormulaDraftFeature.draft("aire d'un cercle de rayon 3", config, transport)
        assertTrue(outcome is JEVOutcome.Erreur && outcome.message.contains("rayon"))
    }
}
