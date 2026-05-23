package be.cobaltfilms.alphanote.domain

/**
 * Formateur pour le mode liste.
 * Portage fidèle de Models/ListModeFormatter.swift (macOS).
 *
 * Normalise le contenu pour l'affichage en mode checklist :
 * - Extraction du header "list" ou "list:"
 * - Parsing des lignes avec commentaires (//) et headings (#)
 * - Split des éléments séparés par des virgules
 */
object ListModeFormatter {

    /**
     * Normalise le contenu pour le mode liste.
     * @param content le contenu brut de la note
     * @param forceListHeader si vrai, force l'ajout d'un header "list"
     * @return le contenu normalisé
     */
    fun normalizeForListMode(content: String, forceListHeader: Boolean = false): String {
        val rawLines = content.lines()
        val nonEmpty = rawLines.firstOrNull { it.trim().isNotEmpty() }?.trim() ?: ""
        val lower = nonEmpty.lowercase()

        val hasListHeader = lower == "list" || lower.startsWith("list:")
        var headerLine = if (hasListHeader) nonEmpty else "list"
        if (forceListHeader && !hasListHeader) {
            headerLine = "list"
        }

        val bodySource: List<String> = if (hasListHeader) {
            val firstIdx = rawLines.indexOfFirst {
                it.trim().lowercase() == lower
            }
            if (firstIdx >= 0) rawLines.drop(firstIdx + 1) else rawLines
        } else {
            rawLines
        }

        val bodyLines = mutableListOf<String>()
        for (line in bodySource) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue

            if (isComment(trimmed) || isHeading(trimmed)) {
                bodyLines.add(trimmed)
                continue
            }

            val commaParts = trimmed
                .split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }

            if (commaParts.isEmpty()) {
                bodyLines.add(trimmed)
            } else {
                bodyLines.addAll(commaParts)
            }
        }

        // Éviter le doublon "list" / "list"
        if (headerLine.trim().lowercase() == "list" &&
            bodyLines.size == 1 &&
            bodyLines[0].trim().lowercase() == "list"
        ) {
            bodyLines.clear()
        }

        return if (bodyLines.isEmpty()) {
            headerLine
        } else {
            (listOf(headerLine) + bodyLines).joinToString("\n")
        }
    }

    fun isListHeader(line: String): Boolean {
        val trimmed = line.trim().lowercase()
        return trimmed == "list" || trimmed.startsWith("list:")
    }

    fun isComment(line: String): Boolean {
        return line.trim().startsWith("//")
    }

    fun isHeading(line: String): Boolean {
        val trimmed = line.trim()
        return trimmed.startsWith("###") || trimmed.startsWith("##") || trimmed.startsWith("#")
    }
}
