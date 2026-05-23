package be.cobaltfilms.alphanote.domain

/**
 * Détecteur de mots-clés — classification de la première ligne d'une note.
 * Portage fidèle de AI/AIIntentDetector.swift (macOS).
 *
 * Détecte le mode (math, list, code, timer) et les intentions IA
 * (webResearch, transform, question) à partir du contenu texte.
 */
object KeywordDetector {

    enum class NoteIntent {
        MATH,
        LIST,
        TRANSFORM,
        WEB_RESEARCH,
        QUESTION
    }

    /** Mots-clés de mode connus — première ligne de la note */
    private val knownKeywords = setOf("math", "list", "code", "timer")

    /**
     * Détecte le mot-clé de mode à partir du contenu brut.
     * @return le mot-clé trouvé, ou vide si aucun.
     */
    fun detectKeyword(content: String): String {
        val rawFirstLine = content.lines().firstOrNull()?.trim() ?: ""
        val firstLine = rawFirstLine.lowercase()

        if (knownKeywords.contains(firstLine)) return firstLine

        val colonIndex = rawFirstLine.indexOf(':')
        if (colonIndex >= 0) {
            val possibleKeyword = rawFirstLine.substring(0, colonIndex).trim().lowercase()
            if (knownKeywords.contains(possibleKeyword)) return possibleKeyword
        }

        return ""
    }

    /**
     * Classifie l'intention d'une question utilisateur.
     * @param question le texte de la question
     * @param noteKeyword le mot-clé de la note courante (peut être null)
     */
    fun classifyIntent(question: String, noteKeyword: String?): NoteIntent {
        val isMathNote = (noteKeyword ?: "").lowercase() == "math"
        if (isMathNote && isMathRequest(question, noteKeyword)) {
            return NoteIntent.MATH
        }

        val web = isWebResearchRequest(question)
        if (web) return NoteIntent.WEB_RESEARCH

        if (isMathRequest(question, noteKeyword)) return NoteIntent.MATH
        if (isListRequest(question, noteKeyword)) return NoteIntent.LIST
        if (isNoteTransformationRequest(question)) return NoteIntent.TRANSFORM

        return NoteIntent.QUESTION
    }

    // ---- Web Research ----

    fun isWebResearchRequest(question: String): Boolean {
        val query = normalized(question)
        val compact = compactNormalized(question)

        // URLs présentes
        if (extractUrls(question).isNotEmpty()) return true

        val directMarkers = listOf(
            "selon le web", "sur le web", "sur internet",
            "web", "internet", "recherche", "rechercher",
            "actualite", "actualité", "news",
            "cette semaine", "aujourd'hui", "a jour", "à jour",
            "recent", "récent"
        )
        if (directMarkers.any { query.contains(it) }) return true

        val typoMarkers = listOf("actu", "actualit", "internet", "web", "recen")
        if (typoMarkers.any { compact.contains(it) }) return true

        return false
    }

    // ---- List ----

    fun isExplicitListRequest(question: String): Boolean {
        val normalized = question.lowercase()

        if (normalized.contains("liste")) return true

        val markers = listOf(
            "fais une liste", "fais moi une liste", "donne moi une liste",
            "liste des ingredients", "liste d'ingredients", "ingredients",
            "checklist", "to-do list", "todo list"
        )
        return markers.any { normalized.contains(it) }
    }

    fun isListRefinementRequest(question: String): Boolean {
        val normalized = question.lowercase()
        val markers = listOf(
            "ajoute", "complete", "ameliore", "améliore",
            "plus de details", "plus de détails", "quantite", "quantité",
            "precise", "précise", "detaille", "détaille"
        )
        return markers.any { normalized.contains(it) }
    }

    fun asksForQuantityDetails(question: String): Boolean {
        val query = normalized(question)
        return query.contains("quantite") || query.contains("quantité") ||
            query.contains("gramme") || query.contains("kg") ||
            query.contains("ml") || query.contains("cuillere") ||
            query.contains("cuillère")
    }

    fun isNoteTransformationRequest(question: String): Boolean {
        val query = normalized(question)
        val markers = listOf(
            "reecris", "réécris", "reformule", "reformuler",
            "corrige", "corriger", "ameliore", "améliore",
            "transforme", "transformer", "resume", "résume",
            "resume-moi", "traduis", "traduire",
            "mets en forme", "structure", "complete", "complète",
            "ajoute", "developpe", "développe", "genere", "génère",
            "fais une version"
        )
        return markers.any { query.contains(it) }
    }

    // ---- Math ----

    fun isMathRequest(question: String, noteKeyword: String?): Boolean {
        val hasUrl = extractUrls(question).isNotEmpty()
        val listLike = isListRequest(question, noteKeyword)
        val isMathNote = (noteKeyword ?: "").lowercase() == "math"
        if (hasUrl && listLike && !isMathNote) return false

        if (isMathNote) return true

        val query = normalized(question)
        val compact = compactNormalized(question)

        val markers = listOf(
            "math", "calcule", "calcul", "combien",
            "pourcentage", "reduction", "réduction",
            "equation", "équation", "convertis",
            "conversion", "to ", " in ", " en "
        )
        if (markers.any { query.contains(it) }) return true

        val typoMathMarkers = listOf(
            "pource", "pourcent", "poucent", "pourent",
            "reduc", "reduct", "remise", "promo",
            "prixbase", "prixfinal", "discount"
        )
        if (typoMathMarkers.any { compact.contains(it) }) return true

        // Expression mathématique : chiffre opérateur chiffre
        if (Regex("\\d+\\s*[\\+\\-\\*\\/\\^]\\s*\\d+").containsMatchIn(query)) return true

        // Heuristique prix
        val hasTwoNumbers = numberCount(query) >= 2
        val hasPriceWords = query.contains("prix") || query.contains("coute") ||
            query.contains("coûte") || query.contains("vend") ||
            query.contains("piece") || query.contains("pièce") ||
            query.contains("base") || query.contains("final")
        val hasCurrency = query.contains("€") || query.contains("$") ||
            query.contains("eur") || query.contains("usd") || query.contains("dh")
        if (hasTwoNumbers && (hasPriceWords || hasCurrency)) return true

        return false
    }

    fun isListRequest(question: String, noteKeyword: String?): Boolean {
        if ((noteKeyword ?: "").lowercase() == "list") return true
        if (isExplicitListRequest(question) || isListRefinementRequest(question)) return true

        val query = normalized(question)
        val compact = compactNormalized(question)

        val markers = listOf(
            "todo", "to-do", "checklist", "liste", "courses",
            "ingredients", "ingrédients", "taches", "tâches"
        )
        if (markers.any { query.contains(it) }) return true

        val typoMarkers = listOf("ingred", "ingredient", "ingr", "list", "checklis", "todo")
        if (typoMarkers.any { compact.contains(it) }) return true

        // Si l'utilisateur a entré des éléments séparés par des virgules
        val commaParts = question.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (commaParts.size >= 3) return true

        return false
    }

    // ---- Helpers ----

    private fun normalized(text: String): String {
        return text.lowercase()
            .replace("é", "e").replace("è", "e").replace("ê", "e")
            .replace("à", "a").replace("â", "a")
            .replace("î", "i").replace("ï", "i")
            .replace("ô", "o").replace("ö", "o")
            .replace("ù", "u").replace("û", "u")
            .replace("ç", "c")
    }

    private fun compactNormalized(text: String): String {
        return normalized(text).replace(Regex("[^\\p{L}\\p{N}]"), "")
    }

    private fun numberCount(text: String): Int {
        return Regex("[-+]?\\d+(?:[.,]\\d+)?").findAll(text).count()
    }

    private fun extractUrls(text: String): List<String> {
        val urlRegex = Regex("https?://[\\w./?=&%\\-+#]+")
        return urlRegex.findAll(text).map { it.value }.toList()
    }
}
