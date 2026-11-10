package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.model.Note
import java.time.Instant
import java.time.ZoneId

/**
 * Façons de ranger la liste des notes. Même liste et mêmes règles que la
 * version Apple (`Models/NoteOrganizer.swift`).
 */
enum class NoteGrouping(val raw: String, val title: String) {
    /** Ordre habituel : épinglées, puis de la plus récente à la plus ancienne. */
    RECENT("recent", "Par date"),
    /** Par rayon : thème écrit dans la note, sinon proposé ([ThemeSorter]). */
    THEME("theme", "Par rayon"),
    /** Par forme : ce qu'est la note (commandes, liste, lien…), pas son sujet. */
    SHAPE("shape", "Par forme"),
    /** Par mois de création. */
    MONTH("month", "Par mois de création"),
    /** Tri à faire : ce qui est probablement à archiver ou à supprimer. */
    TRIAGE("triage", "Tri à faire");

    companion object {
        fun fromRaw(raw: String?): NoteGrouping = entries.firstOrNull { it.raw == raw } ?: RECENT
    }
}

/** Forme d'une note, lue dans son texte : aucun réseau, aucune IA. */
enum class NoteShape(val title: String) {
    TERMINAL("Commandes et code"),
    LIST("Listes"),
    LINK("Liens"),
    ONE_LINE("Une seule ligne"),
    LONG_TEXT("Textes longs"),
    SHORT_TEXT("Textes courts"),
    MATH("Calculs"),
    TIMER("Minuteurs"),
    VAULT("Notes sécurisées")
}

/** Pourquoi une note figure dans le « tri à faire ». */
enum class TriageReason(val title: String) {
    DUPLICATE("Doublons probables"),
    TIMER("Minuteurs"),
    LINK("Liens seuls"),
    ONE_LINE("Une seule ligne")
}

object NoteOrganizer {
    data class Section(val title: String, val noteUuids: List<String>)

    const val LONG_TEXT_LENGTH = 1500
    const val LINK_MAX_LENGTH = 300
    const val ONE_LINE_MAX_LENGTH = 80
    /** Section du tri qui rassemble tout ce qui n'appelle aucun tri. */
    const val KEEP_TITLE = "Le reste"

    private val url = Regex("""https?://\S+""", RegexOption.IGNORE_CASE)

    /** Lignes utiles : sans en-tête de mode, thème, rappels, pièces jointes ni lignes vides. */
    fun meaningfulLines(note: Note): List<String> {
        var lines = note.content.split("\n")
        if (NoteThemes.isModeHeader(NoteThemes.trimSpaces(lines.first()))) lines = lines.drop(1)
        return lines.filter { line ->
            val trimmed = NoteThemes.trimSpaces(line)
            trimmed.isNotEmpty() && !NoteThemes.isThemeLine(line) && !NoteAttachments.isImageLine(line) &&
                !trimmed.lowercase().startsWith("rappel ")
        }
    }

    fun shape(note: Note): NoteShape {
        if (note.isVault) return NoteShape.VAULT
        when (note.keyword) {
            "timer" -> return NoteShape.TIMER
            "math" -> return NoteShape.MATH
            "list" -> return NoteShape.LIST
            "code" -> return NoteShape.TERMINAL
        }
        val lines = meaningfulLines(note)
        val text = lines.joinToString("\n")
        if (ThemeSorter.looksLikeCode(text)) return NoteShape.TERMINAL
        if (shorterThan(text, LINK_MAX_LENGTH) && url.containsMatchIn(text)) return NoteShape.LINK
        if (lines.size >= 4 && lines.count { shorterThan(it, 40) } * 5 >= lines.size * 4) return NoteShape.LIST
        if (lines.size <= 1 && shorterThan(text, ONE_LINE_MAX_LENGTH)) return NoteShape.ONE_LINE
        return if (longerThan(text, LONG_TEXT_LENGTH)) NoteShape.LONG_TEXT else NoteShape.SHORT_TEXT
    }

    /**
     * Raison de trier la note, null si elle n'en appelle aucune. Une note
     * épinglée ou sécurisée n'est jamais proposée au tri. [duplicates] : uuid
     * des doublons (voir [duplicateUuids]).
     */
    fun triageReason(note: Note, duplicates: Set<String>): TriageReason? {
        if (note.isPinned || note.isVault) return null
        if (note.uuid in duplicates) return TriageReason.DUPLICATE
        return when (shape(note)) {
            NoteShape.TIMER -> TriageReason.TIMER
            NoteShape.LINK -> TriageReason.LINK
            NoteShape.ONE_LINE -> if (NoteAttachments.names(note.content).isEmpty()) TriageReason.ONE_LINE else null
            else -> null
        }
    }

    /**
     * Notes dont le début (120 caractères, casse, accents et espaces ignorés)
     * répète celui d'une note plus ancienne : la plus ancienne est gardée.
     */
    fun duplicateUuids(notes: List<Note>): Set<String> {
        val seen = HashSet<String>()
        val duplicates = LinkedHashSet<String>()
        val ordered = notes.filter { !it.isVault }.sortedWith(compareBy<Note> { it.createdAt }.thenBy { it.uuid })
        for (note in ordered) {
            val text = meaningfulLines(note).joinToString(" ")
            if (!longerThan(text, 20)) continue
            val folded = NoteThemes.fold(text).split(' ', '\t').filter { it.isNotEmpty() }.joinToString(" ")
            if (!seen.add(NoteThemes.prefix(folded, 120))) duplicates.add(note.uuid)
        }
        return duplicates
    }

    /**
     * Les notes en sections, dans l'ordre reçu à l'intérieur d'une section.
     * [NoteGrouping.RECENT] rend une seule section sans titre.
     */
    fun sections(
        notes: List<Note>, grouping: NoteGrouping, themes: Map<String, String>, zone: ZoneId = ZoneId.systemDefault()
    ): List<Section> = when (grouping) {
        NoteGrouping.RECENT -> if (notes.isEmpty()) emptyList() else listOf(Section("", notes.map { it.uuid }))
        NoteGrouping.THEME -> NoteThemes.sections(notes.map { it.uuid }, themes).map { Section(it.theme, it.noteUuids) }
        NoteGrouping.SHAPE -> {
            val byShape = notes.groupBy(::shape)
            NoteShape.entries.mapNotNull { shape -> byShape[shape]?.let { Section(shape.title, it.map { note -> note.uuid }) } }
        }
        NoteGrouping.MONTH -> {
            val members = HashMap<Int, MutableList<String>>()
            for (note in notes) {
                val date = Instant.ofEpochMilli(note.createdAt).atZone(zone)
                members.getOrPut(date.year * 12 + date.monthValue - 1) { mutableListOf() }.add(note.uuid)
            }
            members.keys.sortedDescending().map { key -> Section(monthTitle(key / 12, key % 12 + 1), members[key].orEmpty()) }
        }
        NoteGrouping.TRIAGE -> {
            val duplicates = duplicateUuids(notes)
            val members = HashMap<TriageReason, MutableList<String>>()
            val keep = mutableListOf<String>()
            for (note in notes) {
                val reason = triageReason(note, duplicates)
                if (reason != null) members.getOrPut(reason) { mutableListOf() }.add(note.uuid) else keep.add(note.uuid)
            }
            val sections = TriageReason.entries.mapNotNull { reason -> members[reason]?.let { Section(reason.title, it) } }
            if (keep.isEmpty()) sections else sections + Section(KEEP_TITLE, keep)
        }
    }

    private val months = listOf(
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre",
    )

    fun monthTitle(year: Int, month: Int): String = "${months[(month - 1).coerceIn(0, 11)]} $year"

    // Longueurs en caractères affichés, comme côté Apple. Un caractère affiché
    // occupe au moins une unité : le compte exact ne sert qu'au-delà du seuil.
    private fun shorterThan(text: String, limit: Int): Boolean = text.length < limit || NoteThemes.count(text) < limit
    private fun longerThan(text: String, limit: Int): Boolean = text.length > limit && NoteThemes.count(text) > limit
}
