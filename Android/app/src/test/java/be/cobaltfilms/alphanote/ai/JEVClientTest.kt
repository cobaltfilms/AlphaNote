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
        val transport = JEVTransport { _, _, _, _ -> """{"results":[]}""" }
        val outcome = JEVClient.decider(config, "x", ModeRoutingFeature.schema, listOf("minuteur"), transport)
        assertTrue(outcome is JEVOutcome.Erreur)
    }

    @Test
    fun routingFallsBackToKeywordsWithReason() = runBlocking {
        val transport = JEVTransport { _, _, _, _ -> throw JEVHttpError(503) }
        val decision = ModeRoutingFeature.route("minuteur 10 min", null, config, transport)
        assertEquals(NoteMode.TIMER, decision.mode)
        assertEquals(RouteSource.MOTS_CLES, decision.source)
        assertEquals("Le serveur de décision a répondu 503.", decision.echec)
    }

    @Test
    fun routingUsesServerDecision() = runBlocking {
        val transport = JEVTransport { _, body, _, _ ->
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

    @Test
    fun accessTokenIsSentAsCloudflareHeaders() = runBlocking {
        var sent: Map<String, String> = emptyMap()
        val transport = JEVTransport { _, _, _, headers -> sent = headers; """{"results":[{"decision":{"mode":"math"}}]}""" }
        val settings = AISettings(enabled = true, jevUrl = "https://jev.test", accessClientId = "abc.access", accessClientSecret = "s3cret")
        ModeRoutingFeature.route("12 * 8", null, settings.config, transport)
        assertEquals(mapOf("CF-Access-Client-Id" to "abc.access", "CF-Access-Client-Secret" to "s3cret"), sent)
    }

    @Test
    fun forbiddenPointsToAccessToken() = runBlocking {
        val transport = JEVTransport { _, _, _, _ -> throw JEVHttpError(403) }
        val decision = ModeRoutingFeature.route("12 * 8", null, config, transport)
        assertTrue(decision.echec.orEmpty().contains("jeton d'accès"))
    }
}
