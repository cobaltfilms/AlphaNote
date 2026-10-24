package be.cobaltfilms.alphanote.ai

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JEVClientTest {
    private val config = JEVConfig("http://jev.local", 5000)

    @Test
    fun readsValidDecisionsAndIgnoresInvalidValues() {
        val brut = JSONObject("""{"results":[{"decision":{"mode":"math"}},{"decision":{"mode":"chanson"}}]}""")
        val decisions = JEVClient.lireReponse(brut, ModeRoutingFeature.schema, attendus = 2)
        assertEquals(JEVValue.Str("math"), decisions[0]["mode"])
        assertNull(decisions[1]["mode"])
    }

    @Test
    fun incompleteAnswerIsAnError() = runBlocking {
        val transport = JEVTransport { _, _, _ -> """{"results":[]}""" }
        val outcome = JEVClient.decider(config, "x", ModeRoutingFeature.schema, listOf("minuteur"), transport)
        assertTrue(outcome is JEVOutcome.Erreur)
    }

    @Test
    fun routingFallsBackToKeywordsWithReason() = runBlocking {
        val transport = JEVTransport { _, _, _ -> throw JEVHttpError(503) }
        val decision = ModeRoutingFeature.route("minuteur 10 min", null, config, transport)
        assertEquals(NoteMode.TIMER, decision.mode)
        assertEquals(RouteSource.MOTS_CLES, decision.source)
        assertEquals("Le serveur de décision a répondu 503.", decision.echec)
    }

    @Test
    fun routingUsesServerDecision() = runBlocking {
        val transport = JEVTransport { _, body, _ ->
            assertTrue(body.contains("\"contexts\":[\"courses : pain\"]"))
            """{"results":[{"decision":{"mode":"list"}}]}"""
        }
        val decision = ModeRoutingFeature.route("courses : pain", null, config, transport)
        assertEquals(ModeDecision(NoteMode.LIST, RouteSource.JEV), decision)
    }

    @Test
    fun schemaWithoutDescriptionIsRefused() {
        assertEquals("Le champ « x » n'a pas de description.", JEVClient.verifierSchema(mapOf("x" to JEVField.Bool(""))))
        assertNull(JEVClient.verifierSchema(ModeRoutingFeature.schema))
    }
}
