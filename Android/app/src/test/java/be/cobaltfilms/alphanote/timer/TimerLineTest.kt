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
        assertEquals("timer\npomodoro 25:00", TimerRegistry.contentWithTimerLine("timer", TimerSession.Mode.POMODORO, 1500))
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
}
