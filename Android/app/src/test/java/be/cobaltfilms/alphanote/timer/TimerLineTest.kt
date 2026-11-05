package be.cobaltfilms.alphanote.timer

import org.junit.Assert.assertEquals
import org.junit.Test

class TimerLineTest {

    @Test
    fun replacesExistingLineWithSeconds() {
        assertEquals(
            "timer: Oeuf a la coque\ncountdown 4:30\n// mollet",
            TimerRegistry.contentWithTimerLine("timer: Oeuf a la coque\ncountdown 10:00\n// mollet", TimerSession.Mode.COUNTDOWN, 270)
        )
    }

    @Test
    fun addsLineUnderHeaderWhenMissing() {
        assertEquals("timer\ncountdown 25:00", TimerRegistry.contentWithTimerLine("timer", TimerSession.Mode.COUNTDOWN, 1500))
    }

    @Test
    fun stopwatchHasNoDuration() {
        assertEquals("timer\nstopwatch", TimerRegistry.contentWithTimerLine("timer\ncountdown 5:00", TimerSession.Mode.STOPWATCH, 300))
    }

    @Test
    fun leavesOtherTextAlone() {
        assertEquals(
            "timer\nChronologie du tournage\ncountdown 1:35",
            TimerRegistry.contentWithTimerLine("timer\nChronologie du tournage\ncountdown 1:00", TimerSession.Mode.COUNTDOWN, 95)
        )
    }

    @Test
    fun writtenLineReadsBack() {
        val content = TimerRegistry.contentWithTimerLine("timer", TimerSession.Mode.COUNTDOWN, 222)
        assertEquals(TimerSession.Mode.COUNTDOWN to 222, TimerRegistry.parameters(content))
    }

    @Test
    fun alarmLineIsTimeOfDay() {
        assertEquals("timer\nalarm 07:30", TimerRegistry.contentWithTimerLine("timer\ncountdown 5:00", TimerSession.Mode.ALARM, 7 * 3600 + 30 * 60))
        assertEquals(TimerSession.Mode.ALARM to 18 * 3600 + 5 * 60, TimerRegistry.parameters("timer\nalarm 18:05"))
    }

    @Test
    fun legacyPomodoroReadsAsCountdown() {
        assertEquals(TimerSession.Mode.COUNTDOWN to 1500, TimerRegistry.parameters("timer\npomodoro 25:00"))
        assertEquals("timer\nalarm 06:00", TimerRegistry.contentWithTimerLine("timer\npomodoro 25:00", TimerSession.Mode.ALARM, 6 * 3600))
        assertEquals(TimerSession.Mode.COUNTDOWN, TimerSession.Mode.fromStored("POMODORO"))
    }

    @Test
    fun alarmFiresAtNextOccurrence() {
        val now = java.time.ZonedDateTime.of(2026, 11, 5, 8, 0, 0, 0, java.time.ZoneId.of("Europe/Brussels"))
        assertEquals(3600.0, TimerSession.secondsUntil(9 * 3600, now), 0.001)
        assertEquals(23 * 3600.0, TimerSession.secondsUntil(7 * 3600, now), 0.001)
    }
}
