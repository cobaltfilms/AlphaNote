package be.cobaltfilms.alphanote.ai

import be.cobaltfilms.alphanote.domain.MathDocumentEvaluator
import be.cobaltfilms.alphanote.domain.MathEvaluator
import org.json.JSONArray
import org.json.JSONObject

/**
 * Seule exception au contrat JEV (décision de Paul, 2026-10-24) — port de
 * AI/Features/FormulaDraftFeature.swift : en mode math, le modèle du serveur
 * peut RÉDIGER une formule à partir d'une demande en mots. Garde-fous :
 * - la formule n'est gardée que si la note la calcule, et chaque mot doit être
 *   une fonction connue, `pi` ou une variable définie juste au-dessus
 *   (l'évaluateur ignorerait sinon les mots inconnus en silence) ;
 * - elle est écrite sous un commentaire qui dit qu'elle vient de l'IA ;
 * - un échec est franc : rien n'est écrit et l'écran dit pourquoi.
 */
object FormulaDraftFeature {

    /** Lignes de la note math : `nom: expr` puis `expr =` ou `nom: expr =`. */
    data class Draft(val lines: List<String>, val model: String?)

    val systemPrompt = """
        Tu traduis une demande en formule pour la note math d'AlphaNote.
        Réponds uniquement en JSON : {"lignes": ["...", "..."]}.
        Règles :
        - Chaque ligne intermédiaire définit une variable : "nom: expression". Noms en minuscules sans accent, lettres, chiffres et _ uniquement.
        - La dernière ligne donne le résultat : "nom: expression =" (sans le résultat).
        - Convertis vers l'unité demandée (m³ → litres : × 1000 ; minutes → heures : / 60).
        - Opérateurs : + - * / ^ ( ). Décimales avec un point. Pourcentages en décimal (3 % → 0.03).
        - Fonctions : sqrt abs round floor ceil ln log log2 exp sin cos tan min max ; constante pi. Angles en radians.
        - Aucun autre mot, aucune unité, aucun commentaire.
        Exemple : "mensualité d'un prêt de 200000 à 3 % sur 20 ans" →
        {"lignes": ["taux: 0.03 / 12", "mois: 20 * 12", "mensualite: 200000 * taux / (1 - (1 + taux)^(-mois)) ="]}
    """.trimIndent()

    /**
     * Le modèle réfléchit avant de répondre (Qwen3 « thinking ») : 7 à 20 s au
     * lieu d'une, mais sans réflexion il se trompait sur des formules simples
     * (secondes par semaine, m³ → litres). D'où un délai propre.
     */
    const val MINIMUM_DELAI_MS = 60_000
    const val MAX_LINES = 8

    private val VARIABLE_NAME = Regex("^[a-z_][a-z0-9_]*$")
    private val WORD = Regex("[\\p{L}_][\\p{L}\\p{N}_]*")

    suspend fun draft(question: String, config: JEVConfig, transport: JEVTransport = OkHttpJEVTransport): JEVOutcome<Draft> {
        val body = JSONObject()
            .put("messages", JSONArray()
                .put(JSONObject().put("role", "system").put("content", systemPrompt))
                .put(JSONObject().put("role", "user").put("content", question)))
            .put("temperature", 0)
            .put("max_tokens", 4_000)
            .toString()
        val url = config.url.trimEnd('/') + "/v1/chat/completions"

        val raw = try {
            transport.post(url, body, maxOf(config.delaiMs, MINIMUM_DELAI_MS))
        } catch (error: JEVHttpError) {
            return JEVOutcome.Erreur("Le serveur IA a répondu ${error.status}.")
        } catch (_: Exception) {
            return JEVOutcome.Erreur("Le serveur IA n'a pas répondu.")
        }

        val response = try { JSONObject(raw) } catch (_: Exception) { null }
        val content = response?.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
            ?: return JEVOutcome.Erreur("Réponse du serveur IA illisible.")
        val model = response.optString("model").takeIf { it.isNotEmpty() }?.substringAfterLast('/')

        return when (val parsed = parseLines(content)) {
            is JEVOutcome.Ok -> validate(parsed.value)?.let { JEVOutcome.Erreur("Formule de l'IA rejetée : $it.") }
                ?: JEVOutcome.Ok(Draft(parsed.value, model))
            is JEVOutcome.Erreur -> parsed
        }
    }

    // ---- Lecture et contrôle (purs, testés) ----

    fun parseLines(content: String): JEVOutcome<List<String>> {
        // Un éventuel bloc <think>…</think> ou des balises ``` autour du JSON.
        var text = content.replace(Regex("(?s)<think>.*?</think>"), "")
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start >= 0 && end > start) text = text.substring(start, end + 1)
        val array = try { JSONObject(text).optJSONArray("lignes") } catch (_: Exception) { null }
            ?: return JEVOutcome.Erreur("L'IA n'a pas rendu de formule.")
        val lines = (0 until array.length()).mapNotNull { array.opt(it) as? String }.map { it.trim() }.filter { it.isNotEmpty() }
        return if (lines.isEmpty()) JEVOutcome.Erreur("L'IA n'a pas rendu de formule.") else JEVOutcome.Ok(lines)
    }

    /** null si la formule est acceptable, sinon la raison du rejet. */
    fun validate(lines: List<String>): String? {
        if (lines.size > MAX_LINES) return "trop de lignes"
        val last = lines.lastOrNull() ?: return "pas de ligne de résultat"
        if (!last.endsWith("=")) return "pas de ligne de résultat"

        val defined = HashSet<String>()
        lines.forEachIndexed { index, line ->
            val isLast = index == lines.lastIndex
            val assignment = MathDocumentEvaluator.parseVariableAssignment(line)
            val expression = when {
                isLast && assignment != null -> {
                    if (!assignment.showsResult) return "pas de ligne de résultat"
                    assignment.expression
                }
                isLast -> line.dropLast(1).trim().also { if (it.contains('=')) return "ligne de résultat mal formée" }
                else -> {
                    if (assignment == null || assignment.showsResult || !VARIABLE_NAME.matches(assignment.name)) {
                        return "« $line » n'est pas une variable valide"
                    }
                    if (MathEvaluator.isKnownName(assignment.name)) return "« ${assignment.name} » est un nom réservé"
                    assignment.expression
                }
            }
            if (expression.isEmpty()) return "expression vide"
            WORD.findAll(expression).map { it.value }
                .firstOrNull { it !in defined && !MathEvaluator.isKnownName(it) }
                ?.let { return "mot inconnu « $it »" }
            if (!isLast && assignment != null) defined += assignment.name
        }

        // La note doit effectivement calculer la dernière ligne.
        val result = MathDocumentEvaluator().evaluate((listOf("math") + lines).joinToString("\n")).lastOrNull()?.transformed
            ?: return "le calcul n'aboutit pas"
        val equal = result.lastIndexOf('=')
        if (equal < 0 || result.substring(equal + 1).isBlank()) return "le calcul n'aboutit pas"
        return null
    }
}
