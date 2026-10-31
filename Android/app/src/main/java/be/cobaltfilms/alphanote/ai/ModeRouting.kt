package be.cobaltfilms.alphanote.ai

import be.cobaltfilms.alphanote.domain.RecipeIngredientExtractor

import java.text.Normalizer

enum class NoteMode(val keyword: String, val label: String, val title: String) {
    MATH("math", "MATH", "Math"),
    LIST("list", "LISTE", "Liste"),
    TIMER("timer", "TIMER", "Minuteur"),
    CODE("code", "CODE", "Code"),
    PLAIN("", "TEXTE", "Texte"),
    /** Note sécurisée : jamais proposée au serveur JEV (absente de `raws`). */
    VAULT("vault", "COFFRE", "Coffre");

    companion object {
        fun fromKeyword(keyword: String?): NoteMode =
            entries.firstOrNull { it.keyword.isNotEmpty() && it.keyword == keyword?.lowercase() } ?: PLAIN

        fun fromRaw(raw: String): NoteMode? = when (raw) {
            "math" -> MATH; "list" -> LIST; "timer" -> TIMER; "code" -> CODE; "plain" -> PLAIN
            else -> null
        }

        val raws: List<String> = listOf("math", "list", "timer", "code", "plain")
    }
}

enum class RouteSource(val label: String) { JEV("JEV"), LOCAL("modèle local"), MOTS_CLES("mots-clés") }

data class ModeDecision(val mode: NoteMode, val source: RouteSource, val echec: String? = null)

/**
 * Routage de mode à la JEV : le serveur CLASSE la demande, il ne rédige rien.
 * En cas d'échec, repli franc sur les mots-clés, et la décision dit d'où elle vient.
 */
object ModeRoutingFeature {
    const val instructions = """Classe la demande de l'utilisateur dans un seul mode d'une note AlphaNote.
Réponds uniquement selon le schéma, sans rédiger. En cas de doute, plain."""

    val modeField = JEVField.Str(
        choices = NoteMode.raws,
        description = """Le mode que la demande appelle.
- math : la demande cherche un résultat chiffré — calcul, pourcentage, réduction, écart de prix, conversion d'unités ou de devises, ou une formule décrite en mots (aire, volume, mensualité, intérêts…). Exemples : « 12 * 8 », « pourcentage de réduction entre 120 et 90 », « 10 km to mi », « aire d'un cercle de rayon 3 ».
- list : la demande veut une liste, une check-list, des tâches, des courses, des ingrédients, ajouter des éléments à une liste, ou contient le lien d'une recette (ses ingrédients deviennent la liste). Exemples : « courses : tomates, pâtes, huile », « ajoute de l'huile d'olive à la liste », « https://www.marmiton.org/recettes/recette_crepes.aspx ».
- timer : la demande veut un minuteur, un compte à rebours, un chronomètre ou une session pomodoro. Exemples : « minuteur 25 minutes », « lance un chrono ».
- code : la demande écrit, corrige ou range un snippet de code ou une commande.
- plain : cas par défaut — une pensée, une question, du texte, une note qui ne correspond à aucun autre mode."""
    )

    val schema: JEVSchema get() = mapOf("mode" to modeField)

    suspend fun route(
        question: String, noteKeyword: String?, config: JEVConfig?, transport: JEVTransport = OkHttpJEVTransport,
        local: ((String) -> LocalModeClassifier.Decision?)? = null
    ): ModeDecision {
        val trimmed = question.trim()
        if (trimmed.isEmpty()) return ModeDecision(NoteMode.PLAIN, RouteSource.MOTS_CLES)

        var echec: String? = null
        if (config != null) {
            when (val outcome = JEVClient.decider(config, instructions, schema, listOf(trimmed), transport)) {
                is JEVOutcome.Ok -> {
                    val raw = (outcome.value.firstOrNull()?.get("mode") as? JEVValue.Str)?.value
                    val mode = raw?.let { NoteMode.fromRaw(it) }
                    if (mode != null) return ModeDecision(mode, RouteSource.JEV)
                    echec = "Le serveur n'a pas désigné de mode valide."
                }
                is JEVOutcome.Erreur -> echec = outcome.message
            }
        }
        // Sans serveur (ou s'il a échoué) : le modèle local du téléphone.
        local?.invoke(trimmed)?.takeIf { it.confidence >= LocalModeClassifier.MINIMUM_CONFIDENCE }?.let {
            return ModeDecision(it.mode, RouteSource.LOCAL, echec)
        }
        return ModeDecision(KeywordIntentRouter.classify(trimmed, noteKeyword), RouteSource.MOTS_CLES, echec)
    }
}

/** Routage de secours par mots-clés — port de AI/KeywordIntentRouter.swift. */
object KeywordIntentRouter {
    enum class TimerType { COUNTDOWN, STOPWATCH, POMODORO }

    fun classify(question: String, noteKeyword: String?): NoteMode = when {
        // Un lien = une recette à lire en liste ; avant les maths, qu'une URL
        // (chiffres, « / », « - ») déclencherait.
        RecipeIngredientExtractor.firstUrl(question) != null -> NoteMode.LIST
        isTimerRequest(question, noteKeyword) -> NoteMode.TIMER
        isMathRequest(question, noteKeyword) -> NoteMode.MATH
        isListRequest(question, noteKeyword) -> NoteMode.LIST
        else -> NoteMode.PLAIN
    }

    fun isMathRequest(question: String, noteKeyword: String?): Boolean {
        if (noteKeyword.orEmpty().lowercase() == "math") return true
        val query = normalized(question)
        val markers = listOf("math", "calcule", "calcul", "combien", "pourcentage", "reduction", "equation", "convertis", "conversion")
        if (markers.any { query.contains(it) }) return true
        if (Regex("\\d+\\s*[+\\-*/^]\\s*\\d+").containsMatchIn(query)) return true
        if (Regex("\\d+\\s*[a-zA-Z°\"'²³]+\\s*(?:to|in|en)\\s*[a-zA-Z°\"'²³]+").containsMatchIn(query)) return true
        return false
    }

    fun isListRequest(question: String, noteKeyword: String?): Boolean {
        if (noteKeyword.orEmpty().lowercase() == "list") return true
        val query = normalized(question)
        val markers = listOf("todo", "to-do", "checklist", "liste", "courses", "ingredients", "taches")
        if (markers.any { query.contains(it) }) return true
        return question.split(",").map { it.trim() }.count { it.isNotEmpty() } >= 3
    }

    fun isTimerRequest(question: String, noteKeyword: String?): Boolean {
        if (noteKeyword.orEmpty().lowercase() == "timer") return true
        val query = normalized(question)
        val markers = listOf("timer", "minuteur", "chrono", "pomodoro", "countdown", "stopwatch")
        if (markers.any { query.contains(it) }) return true
        val patterns = listOf(Regex("\\d+\\s*(min|minute|mn)\\b"), Regex("\\d+\\s*(sec|secondes?)\\b"), Regex("\\d+\\s*(h|heure|hour)s?\\b"))
        return patterns.any { it.containsMatchIn(query) }
    }

    fun parseTimerRequest(question: String): Pair<TimerType, Int> {
        val query = normalized(question)
        val type = when {
            query.contains("pomodoro") -> TimerType.POMODORO
            query.contains("stopwatch") || query.contains("chrono") -> TimerType.STOPWATCH
            else -> TimerType.COUNTDOWN
        }
        var totalSeconds = 0
        val patterns = listOf(
            Regex("(\\d+)\\s*(?:h|heure|hour)s?", RegexOption.IGNORE_CASE) to "hour",
            Regex("(\\d+)\\s*(?:min|minute|mn)s?", RegexOption.IGNORE_CASE) to "min",
            Regex("(\\d+)\\s*(?:sec|secondes?)s?", RegexOption.IGNORE_CASE) to "sec",
            Regex("(\\d+)s", RegexOption.IGNORE_CASE) to "sec"
        )
        for ((regex, unit) in patterns) {
            val digits = regex.find(query)?.groupValues?.get(1)?.toIntOrNull() ?: continue
            if (digits <= 0) continue
            when (unit) {
                "hour" -> totalSeconds += digits * 3600
                "min" -> totalSeconds += digits * 60
                "sec" -> totalSeconds = maxOf(totalSeconds, digits)
            }
        }
        if (totalSeconds == 0) totalSeconds = 10 * 60
        return type to totalSeconds
    }

    fun normalized(text: String): String =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
}
