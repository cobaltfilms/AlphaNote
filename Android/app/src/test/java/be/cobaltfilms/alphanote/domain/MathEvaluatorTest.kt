package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class MathEvaluatorTest {

    private val evaluator = MathEvaluator()

    @Test
    fun evaluate_basicExpression_returnsResult() {
        val result = evaluator.evaluate("2+2")
        assertNotNull(result)
        assertEquals(4.0, result!!, 0.000001)
    }

    @Test
    fun evaluate_parentheses_respectsPrecedence() {
        val result = evaluator.evaluate("(3+4)*2")
        assertNotNull(result)
        assertEquals(14.0, result!!, 0.000001)
    }

    @Test
    fun evaluate_percentageExpression_returnsExpectedValue() {
        val result = evaluator.evaluate("50% of 200")
        assertNotNull(result)
        assertEquals(100.0, result!!, 0.000001)
    }

    @Test
    fun evaluate_withVariables_returnsResult() {
        val result = evaluator.evaluate("a+b", mapOf("a" to 2.0, "b" to 3.0))
        assertNotNull(result)
        assertEquals(5.0, result!!, 0.000001)
    }
}
