package be.cobaltfilms.alphanote.domain

import org.json.JSONArray
import org.json.JSONObject

/**
 * Parseur de réponses LLM.
 * Portage fidèle de AI/AIResponseParser.swift (macOS).
 *
 * Parse le JSON produit par le modèle et en extrait le contenu structuré.
 * Supporte un fallback robuste en texte brut si le JSON est imparfait.
 */
object AIResponseParser {

    /**
     * Résultat parsé d'une réponse IA.
     *
     * @param text le texte principal de la réponse
     * @param metadata métadonnées extraites du JSON
     */
    data class AIResult(
        val text: String,
        val metadata: Map<String, String> = emptyMap()
    )

    /**
     * Parse une réponse brute pour une tâche donnée.
     */
    fun parse(raw: String, task: AITask): AIResult {
        val cleaned = sanitize(raw)
        if (cleaned.isBlank()) return AIResult("", mapOf("error" to "invalid_output"))

        return when (task) {
            is AITask.EXTRACT_ACTIONS -> parseActions(cleaned)
            is AITask.MODE_ROUTING -> parseModeRouting(cleaned)
            is AITask.SEMANTIC_ANSWER -> parseSemanticAnswer(cleaned)
            else -> AIResult(cleaned, emptyMap())
        }
    }

    // ---- Actions ----

    private fun parseActions(raw: String): AIResult {
        return try {
            val json = JSONObject(raw)
            val actionsArray = json.optJSONArray("actions") ?: JSONArray()

            val lines = mutableListOf<String>()
            for (i in 0 until actionsArray.length()) {
                val item = actionsArray.getJSONObject(i)
                val priority = item.optString("priority", "medium").ifEmpty { "medium" }
                val owner = item.optString("owner", "non assigné").ifEmpty { "non assigné" }
                val deadline = item.optString("deadline", "non définie").ifEmpty { "non définie" }
                val title = item.optString("title", "")
                lines.add("${i + 1}. [$priority] $title — owner: $owner, échéance: $deadline")
            }

            val text = if (lines.isEmpty()) "Aucune action détectée." else lines.joinToString("\n")
            AIResult(text, mapOf("format" to "json_actions"))
        } catch (e: Exception) {
            // Fallback texte brut
            AIResult(raw, mapOf("format" to "text_fallback"))
        }
    }

    // ---- Semantic Answer ----

    private fun parseSemanticAnswer(raw: String): AIResult {
        val normalizedJson = stripCodeFence(raw)

        return try {
            val json = JSONObject(normalizedJson)
            val answer = json.optString("answer", "").trim()
            val opJson = json.optJSONObject("operation")
            val opType = opJson?.optString("type", "")?.trim()?.lowercase() ?: ""
            val opContent = sanitize(opJson?.optString("content", "") ?: "")
            val opTitle = opJson?.optString("title", "")?.trim() ?: ""
            val sources = json.optJSONArray("sources")
            val sourcesStr = if (sources != null) {
                (0 until sources.length()).map { sources.getString(it) }.joinToString(",")
            } else ""

            val safeAnswer = if (answer.isEmpty()) opContent else answer

            AIResult(
                text = safeAnswer,
                metadata = mapOf(
                    "format" to "json_semantic",
                    "operation_type" to opType,
                    "operation_content" to opContent,
                    "operation_title" to opTitle,
                    "sources" to sourcesStr
                )
            )
        } catch (e: Exception) {
            // Tente d'extraire un JSON embedded dans du texte
            val extracted = extractJsonPayload(raw)
            if (extracted != null) {
                try {
                    return parseSemanticAnswer(extracted)
                } catch (_: Exception) {}
            }
            AIResult(raw, mapOf("format" to "text_fallback"))
        }
    }

    // ---- Mode Routing ----

    private fun parseModeRouting(raw: String): AIResult {
        val normalizedJson = stripCodeFence(raw)

        return try {
            val json = JSONObject(normalizedJson)
            val modesArray = json.optJSONArray("modes")
            val allowed = setOf("math", "list", "web", "qa", "transform")

            val modes = if (modesArray != null) {
                (0 until modesArray.length())
                    .map { modesArray.getString(it).trim().lowercase() }
                    .filter { it in allowed }
                    .distinct()
            } else emptyList()

            val confidence = json.optDouble("confidence", 0.0).toString()
            val reason = sanitize(json.optString("reason", ""))

            AIResult(
                text = reason,
                metadata = mapOf(
                    "format" to "json_mode_routing",
                    "modes" to modes.joinToString(","),
                    "confidence" to confidence
                )
            )
        } catch (e: Exception) {
            AIResult(raw, mapOf("format" to "text_fallback"))
        }
    }

    // ---- Helpers ----

    private fun sanitize(raw: String): String {
        var value = raw
        // Supprimer les balises  thinking / 
        value = Regex(""" thinking[\s\S]*? response""", RegexOption.IGNORE_CASE).replace(value, "")
        value = Regex("""</?think>""", RegexOption.IGNORE_CASE).replace(value, "")
        return value.trim()
    }

    /** Supprime les backticks de code fence ```json ... ``` */
    private fun stripCodeFence(raw: String): String {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("```") || !trimmed.endsWith("```")) return trimmed

        val lines = trimmed.lines()
        if (lines.size < 2) return trimmed
        return lines.drop(1).dropLast(1).joinToString("\n").trim()
    }

    /**
     * Extrait un objet JSON du milieu d'un texte.
     * Gère l'échappement de chaînes et la profondeur des accolades.
     */
    private fun extractJsonPayload(raw: String): String? {
        val start = raw.indexOf('{')
        if (start < 0) return null

        var depth = 0
        var inString = false
        var escaping = false

        for (i in start until raw.length) {
            val ch = raw[i]
            when {
                inString -> {
                    if (escaping) { escaping = false; continue }
                    if (ch == '\\') { escaping = true; continue }
                    if (ch == '"') { inString = false }
                }
                ch == '"' -> inString = true
                ch == '{' -> depth++
                ch == '}' -> {
                    depth--
                    if (depth == 0) {
                        return raw.substring(start, i + 1).trim()
                    }
                }
            }
        }
        return null
    }
}
