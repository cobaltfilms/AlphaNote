package be.cobaltfilms.alphanote.ai

import org.junit.Assert.assertEquals
import org.junit.Test

class KeywordIntentRouterTest {
    @Test fun classifiesTimer() = assertEquals(NoteMode.TIMER, KeywordIntentRouter.classify("lance un chrono", null))
    @Test fun classifiesMath() = assertEquals(NoteMode.MATH, KeywordIntentRouter.classify("calcule 20% de 50", null))
    @Test fun classifiesConversionAsMath() = assertEquals(NoteMode.MATH, KeywordIntentRouter.classify("12 km to mi", null))
    @Test fun classifiesList() = assertEquals(NoteMode.LIST, KeywordIntentRouter.classify("courses : pain, lait, œufs", null))
    @Test fun defaultsToPlain() = assertEquals(NoteMode.PLAIN, KeywordIntentRouter.classify("une pensée en passant", null))
    @Test fun noteKeywordWins() = assertEquals(NoteMode.MATH, KeywordIntentRouter.classify("une pensée", "math"))

    @Test
    fun parsesTimerDurations() {
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 25 * 60, KeywordIntentRouter.parseTimerRequest("minuteur 25 min"))
        assertEquals(KeywordIntentRouter.TimerType.POMODORO to 25 * 60, KeywordIntentRouter.parseTimerRequest("pomodoro 25 minutes"))
        assertEquals(KeywordIntentRouter.TimerType.STOPWATCH to 10 * 60, KeywordIntentRouter.parseTimerRequest("chrono"))
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 90 * 60, KeywordIntentRouter.parseTimerRequest("1 h 30 min"))
    }
}
