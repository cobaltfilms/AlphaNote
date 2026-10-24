package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class MathEvaluatorTest {
    private val evaluator = MathEvaluator()

    private fun eval(expression: String): Double {
        val result = evaluator.evaluate(expression)
        assertNotNull("« $expression » devrait s'évaluer", result)
        return result!!
    }

    @Test fun basicExpression() = assertEquals(4.0, eval("2+2"), 1e-9)
    @Test fun parenthesesRespectPrecedence() = assertEquals(14.0, eval("(3+4)*2"), 1e-9)
    @Test fun percentageOf() = assertEquals(100.0, eval("50% of 200"), 1e-9)
    @Test fun percentageSubtraction() = assertEquals(80.0, eval("100 - 20%"), 1e-9)
    @Test fun functionsAndConstants() {
        assertEquals(4.0, eval("sqrt(16)"), 1e-9)
        assertEquals(3.0, eval("max(1, 3, 2)"), 1e-9)
        assertEquals(2.0, eval("log(100)"), 1e-9)
        assertEquals(Math.PI * 2, eval("2 pi"), 1e-9)
    }
    @Test fun factorialAndPower() {
        assertEquals(120.0, eval("5!"), 1e-9)
        assertEquals(512.0, eval("2^3^2"), 1e-9)
    }
    @Test fun implicitMultiplication() = assertEquals(14.0, eval("2(3+4)"), 1e-9)
    @Test fun decimalComma() = assertEquals(3.0, eval("1,5 * 2"), 1e-9)
    @Test fun unknownWordsAreIgnored() = assertEquals(8.0, eval("5 pommes + 3"), 1e-9)
    @Test fun unknownFunctionFails() = assertNull(evaluator.evaluate("foo(3)"))
    @Test fun divisionByZeroFails() = assertNull(evaluator.evaluate("1/0"))
}
