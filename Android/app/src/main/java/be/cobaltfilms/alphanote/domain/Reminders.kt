package be.cobaltfilms.alphanote.domain

import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** Nature d'une alerte. Une alerte peut en combiner plusieurs. */
enum class ReminderKind(val raw: String) {
    NOTIFICATION("notification"),
    SONNERIE("sonnerie"),
    VIBRATION("vibration");

    companion object {
        fun fromRaw(raw: String): ReminderKind? = entries.firstOrNull { it.raw == raw.trim().lowercase() }
    }
}

/** Un rappel : une date et heure locales, et les natures d'alerte à cette heure. */
data class Reminder(val at: LocalDateTime, val kinds: Set<ReminderKind>)

/**
 * Rappels stockés dans le texte de la note, une ligne chacun :
 *
 *     rappel 2026-11-10 18:00 : notification, sonnerie, vibration
 *
 * Le texte est synchronisé tel quel (Nextcloud, LAN) : chaque appareil
 * reprogramme ses propres alarmes à partir de ces lignes.
 */
object Reminders {
    private val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    private val line = Regex("""^\s*rappel\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s*:\s*(.+?)\s*$""", RegexOption.IGNORE_CASE)

    /** Rappels de la note, dans l'ordre du texte. Une ligne mal formée est ignorée. */
    fun parse(content: String): List<Reminder> = content.lines().mapNotNull { raw ->
        val match = line.matchEntire(raw) ?: return@mapNotNull null
        val at = runCatching { LocalDateTime.parse(match.groupValues[1], stamp) }.getOrNull() ?: return@mapNotNull null
        val kinds = match.groupValues[2].split(',').mapNotNull { ReminderKind.fromRaw(it) }.toSet()
        if (kinds.isEmpty()) null else Reminder(at, kinds)
    }

    /** La ligne de rappel, sans retour à la ligne. Les natures sont écrites dans l'ordre de [ReminderKind]. */
    fun line(at: LocalDateTime, kinds: Set<ReminderKind>): String {
        val names = ReminderKind.entries.filter { it in kinds }.joinToString(", ") { it.raw }
        return "rappel ${at.format(stamp)} : $names"
    }

    /** Ajoute un rappel en fin de texte, sur sa propre ligne. */
    fun withReminder(content: String, at: LocalDateTime, kinds: Set<ReminderKind>): String {
        val separator = if (content.isEmpty() || content.endsWith("\n")) "" else "\n"
        return content + separator + line(at, kinds)
    }
}
