package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MathDocumentEvaluatorTest {
    private val rates = CurrencyRateService(persists = false)
    private val evaluator = MathDocumentEvaluator(Converter(rates))

    @Test
    fun variablesPercentAndInlineResults() {
        val content = """
            math: Budget
            loyer: 900
            cachets: 3 * 450
            total: loyer + cachets =
            tva: 21%
            total + tva =
        """.trimIndent()
        val lines = evaluator.transformed(content).split("\n")
        assertEquals("total: loyer + cachets = 2250", lines[3])
        assertEquals("total + tva = 2722.5", lines[5])
    }

    @Test
    fun unitsFollowFirstAppearanceAndIncompatibleUnitsWarn() {
        assertEquals("10 kg + 500 g = 10.5 kg", evaluator.transformed("10 kg + 500 g ="))
        assertEquals("12 km to mi = 7.4565 mi", evaluator.transformed("12 km to mi ="))
        assertEquals("3 kg + 2 km = ⚠︎ unités incompatibles", evaluator.transformed("3 kg + 2 km ="))
    }

    @Test
    fun currencyShowsPendingMarkerUntilRatesArrive() {
        assertEquals("100 USD to EUR = …", evaluator.transformed("100 USD to EUR ="))
        rates.seed("USD", mapOf("EUR" to 0.9))
        assertEquals("100 USD to EUR = 90 EUR", evaluator.transformed("100 USD to EUR ="))
    }

    @Test
    fun unevaluableLineClearsItsResult() {
        assertEquals("abc + =", evaluator.transformed("abc + = 12"))
    }

    @Test
    fun inlineApplierReplacesOnlyTailsAndRespectsCaret() {
        val text = "math\n2 + 2 =\n3 * 3 = 9"
        val outcome = MathInlineApplier.apply(text, text.length, evaluator, respectCaret = false)
        assertTrue(outcome.changed)
        assertEquals("math\n2 + 2 = 4\n3 * 3 = 9", outcome.text)

        // Le curseur est dans le résultat existant : on attend qu'il en sorte.
        val editing = "math\n2 + 2 = 41"
        val caretInside = editing.length
        assertFalse(MathInlineApplier.apply(editing, caretInside, evaluator, respectCaret = true).changed)
        assertTrue(MathInlineApplier.apply(editing, 0, evaluator, respectCaret = true).changed)
    }
}
