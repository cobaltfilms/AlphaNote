package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

class RemindersTest {

    private val at = LocalDateTime.of(2026, 11, 10, 18, 0)

    @Test fun parsesEachLineAsOneReminder() {
        val content = "courses\nrappel 2026-11-10 18:00 : notification, sonnerie\nrappel 2026-11-11 09:30 : vibration"
        assertEquals(
            listOf(
                Reminder(at, setOf(ReminderKind.NOTIFICATION, ReminderKind.SONNERIE)),
                Reminder(LocalDateTime.of(2026, 11, 11, 9, 30), setOf(ReminderKind.VIBRATION))
            ),
            Reminders.parse(content)
        )
    }

    @Test fun ignoresMalformedLines() {
        val content = """
            rappel 2026-13-40 18:00 : sonnerie
            rappel 2026-11-10 18h : sonnerie
            rappel 2026-11-10 18:00 : clignotant
            rappel 2026-11-10 18:00 :
            rappel 2026-11-10 18:00 : sonnerie
        """.trimIndent()
        assertEquals(listOf(Reminder(at, setOf(ReminderKind.SONNERIE))), Reminders.parse(content))
    }

    @Test fun unknownKindsAreDroppedButValidOnesKept() {
        val content = "rappel 2026-11-10 18:00 : notification, clignotant, VIBRATION"
        assertEquals(
            listOf(Reminder(at, setOf(ReminderKind.NOTIFICATION, ReminderKind.VIBRATION))),
            Reminders.parse(content)
        )
    }

    @Test fun keywordIsCaseInsensitiveAndWhitespaceTolerant() {
        assertEquals(1, Reminders.parse("  Rappel   2026-11-10 18:00  :  sonnerie  ").size)
    }

    @Test fun lineWritesKindsInFixedOrder() {
        val line = Reminders.line(at, setOf(ReminderKind.VIBRATION, ReminderKind.NOTIFICATION, ReminderKind.SONNERIE))
        assertEquals("rappel 2026-11-10 18:00 : notification, sonnerie, vibration", line)
    }

    @Test fun roundTripsThroughParse() {
        val kinds = setOf(ReminderKind.SONNERIE, ReminderKind.VIBRATION)
        assertEquals(listOf(Reminder(at, kinds)), Reminders.parse(Reminders.line(at, kinds)))
    }

    @Test fun withReminderAppendsOnItsOwnLine() {
        val text = Reminders.withReminder("liste de courses", at, setOf(ReminderKind.NOTIFICATION))
        assertEquals("liste de courses\nrappel 2026-11-10 18:00 : notification", text)
    }

    @Test fun withReminderKeepsExistingTrailingNewline() {
        val text = Reminders.withReminder("texte\n", at, setOf(ReminderKind.NOTIFICATION))
        assertEquals("texte\nrappel 2026-11-10 18:00 : notification", text)
    }

    @Test fun withReminderOnEmptyNoteHasNoLeadingNewline() {
        assertTrue(Reminders.withReminder("", at, setOf(ReminderKind.SONNERIE)).startsWith("rappel "))
    }
}
