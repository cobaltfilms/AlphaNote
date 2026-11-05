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
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 10 * 60, KeywordIntentRouter.parseTimerRequest("lance le minuteur"))
        assertEquals(KeywordIntentRouter.TimerType.STOPWATCH to 10 * 60, KeywordIntentRouter.parseTimerRequest("chrono"))
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 90 * 60, KeywordIntentRouter.parseTimerRequest("1 h 30 min"))
    }

    @Test
    fun parsesAlarmTimes() {
        val alarm = KeywordIntentRouter.TimerType.ALARM
        assertEquals(alarm to 7 * 3600 + 30 * 60, KeywordIntentRouter.parseTimerRequest("réveille-moi à 7h30"))
        assertEquals(alarm to 14 * 3600, KeywordIntentRouter.parseTimerRequest("alarme à 14h"))
        assertEquals(alarm to 18 * 3600 + 15 * 60, KeywordIntentRouter.parseTimerRequest("sonne à 18:15"))
        assertEquals(alarm to 19 * 3600, KeywordIntentRouter.parseTimerRequest("alarme à 7 h du soir"))
        assertEquals(alarm to 12 * 3600, KeywordIntentRouter.parseTimerRequest("rappelle-moi à midi"))
        // « dans » : une durée, pas une heure.
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 10 * 60, KeywordIntentRouter.parseTimerRequest("alarme dans 10 minutes"))
        assertEquals(KeywordIntentRouter.TimerType.COUNTDOWN to 2 * 3600, KeywordIntentRouter.parseTimerRequest("mets un minuteur pour 2h"))
        assertEquals(NoteMode.TIMER, KeywordIntentRouter.classify("réveille-moi à 6h45", null))
        assertEquals(NoteMode.TIMER, KeywordIntentRouter.classify("sonne à 18h15", null))
    }
}
