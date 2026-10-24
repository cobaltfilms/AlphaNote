package be.cobaltfilms.alphanote.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Client du serveur de décision « JEV » — port fidèle de AI/JEVClient.swift.
 * Le serveur **classe** selon un schéma strict, il ne rédige jamais.
 * Une réponse incomplète est un échec ; un serveur injoignable n'empêche
 * jamais l'app de tourner.
 */
sealed class JEVValue {
    data class Str(val value: String) : JEVValue()
    data class Bool(val value: Boolean) : JEVValue()
    data class Integer(val value: Int) : JEVValue()
    data class Number(val value: Double) : JEVValue()
}

sealed class JEVField(val description: String) {
    class Str(val choices: List<String>, description: String) : JEVField(description)
    class Bool(description: String) : JEVField(description)
    class Integer(description: String, val minimum: Int, val maximum: Int) : JEVField(description)
    class Number(description: String, val minimum: Double, val maximum: Double) : JEVField(description)

    fun toJson(): JSONObject = when (this) {
        is Str -> JSONObject().put("type", "enum").put("choices", JSONArray(choices)).put("description", description)
        is Bool -> JSONObject().put("type", "boolean").put("description", description)
        is Integer -> JSONObject().put("type", "integer").put("description", description).put("minimum", minimum).put("maximum", maximum)
        is Number -> JSONObject().put("type", "number").put("description", description).put("minimum", minimum).put("maximum", maximum)
    }
}

typealias JEVSchema = Map<String, JEVField>
typealias JEVDecision = Map<String, JEVValue>

sealed class JEVOutcome<out T> {
    data class Ok<T>(val value: T) : JEVOutcome<T>()
    data class Erreur(val message: String) : JEVOutcome<Nothing>()
}

data class JEVConfig(val url: String, val delaiMs: Int)

fun interface JEVTransport {
    /** POST JSON ; lève en cas d'erreur réseau, retourne le corps sinon. */
    suspend fun post(url: String, body: String, delaiMs: Int): String
}

class JEVHttpError(val status: Int) : Exception("HTTP $status")

object OkHttpJEVTransport : JEVTransport {
    private val json = "application/json; charset=utf-8".toMediaType()

    override suspend fun post(url: String, body: String, delaiMs: Int): String = withContext(Dispatchers.IO) {
        val client = OkHttpClient.Builder()
            .connectTimeout(delaiMs.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(delaiMs.toLong(), TimeUnit.MILLISECONDS)
            .build()
        val request = Request.Builder().url(url).post(body.toRequestBody(json)).build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw JEVHttpError(response.code)
            response.body?.string().orEmpty()
        }
    }
}

object JEVClient {

    fun verifierSchema(schema: JEVSchema): String? {
        if (schema.isEmpty()) return "Le schéma ne décrit aucun champ."
        for ((nom, champ) in schema) {
            if (champ.description.isBlank()) return "Le champ « $nom » n'a pas de description."
            when (champ) {
                is JEVField.Str -> if (champ.choices.size < 2) return "Le champ « $nom » doit proposer au moins deux valeurs."
                is JEVField.Integer -> if (champ.minimum >= champ.maximum) return "Le champ « $nom » doit borner ses valeurs."
                is JEVField.Number -> if (champ.minimum >= champ.maximum) return "Le champ « $nom » doit borner ses valeurs."
                is JEVField.Bool -> Unit
            }
        }
        return null
    }

    suspend fun decider(
        config: JEVConfig,
        instructions: String,
        schema: JEVSchema,
        fragments: List<String>,
        transport: JEVTransport = OkHttpJEVTransport
    ): JEVOutcome<List<JEVDecision>> {
        if (fragments.isEmpty()) return JEVOutcome.Ok(emptyList())
        verifierSchema(schema)?.let { return JEVOutcome.Erreur(it) }

        val schemaJson = JSONObject()
        schema.forEach { (nom, champ) -> schemaJson.put(nom, champ.toJson()) }
        val body = JSONObject()
            .put("instructions", instructions)
            .put("schema", schemaJson)
            .put("contexts", JSONArray(fragments))
            .put("temperature", 1.0)
            .toString()

        val url = config.url.trimEnd('/') + "/v1/decision"
        return try {
            val raw = transport.post(url, body, config.delaiMs)
            val brut = JSONObject(raw)
            val rendus = brut.optJSONArray("results")?.length() ?: 0
            if (rendus < fragments.size) {
                JEVOutcome.Erreur("Le serveur de décision n'a répondu que pour $rendus fragment(s) sur ${fragments.size}.")
            } else {
                JEVOutcome.Ok(lireReponse(brut, schema, fragments.size))
            }
        } catch (error: JEVHttpError) {
            JEVOutcome.Erreur("Le serveur de décision a répondu ${error.status}.")
        } catch (_: Exception) {
            JEVOutcome.Erreur("Le serveur de décision n'a pas répondu.")
        }
    }

    /** Une décision par fragment ; champ absent ou invalide → ignoré. */
    fun lireReponse(brut: JSONObject, schema: JEVSchema, attendus: Int): List<JEVDecision> {
        val results = brut.optJSONArray("results") ?: JSONArray()
        val out = mutableListOf<JEVDecision>()
        for (index in 0 until attendus) {
            val decisionBrute = if (index < results.length()) results.optJSONObject(index)?.optJSONObject("decision") else null
            val decision = mutableMapOf<String, JEVValue>()
            if (decisionBrute != null) {
                for ((nom, champ) in schema) {
                    if (!decisionBrute.has(nom) || decisionBrute.isNull(nom)) continue
                    val valeur = decisionBrute.get(nom)
                    when (champ) {
                        is JEVField.Str -> if (valeur is String && champ.choices.contains(valeur)) decision[nom] = JEVValue.Str(valeur)
                        is JEVField.Bool -> if (valeur is Boolean) decision[nom] = JEVValue.Bool(valeur)
                        is JEVField.Integer -> when (valeur) {
                            is Int -> decision[nom] = JEVValue.Integer(valeur)
                            is Long -> decision[nom] = JEVValue.Integer(valeur.toInt())
                            is Double -> decision[nom] = JEVValue.Integer(Math.round(valeur).toInt())
                        }
                        is JEVField.Number -> when (valeur) {
                            is Double -> decision[nom] = JEVValue.Number(valeur)
                            is Int -> decision[nom] = JEVValue.Number(valeur.toDouble())
                            is Long -> decision[nom] = JEVValue.Number(valeur.toDouble())
                        }
                    }
                }
            }
            out.add(decision)
        }
        return out
    }
}
