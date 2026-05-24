package be.cobaltfilms.alphanote.domain

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ConverterTest {

    private val converter = Converter()

    @Test
    fun convert_lengthConversion_returnsExpectedValue() = runBlocking {
        val result = converter.convert("1 km to m")
        assertEquals("1000 m", result)
    }

    @Test
    fun convert_temperatureConversion_usesOffsetFormula() = runBlocking {
        val result = converter.convert("30 c to f")
        assertEquals("86 °F", result)
    }

    @Test
    fun convert_temperatureFahrenheitToCelsius_returnsRoundedValue() = runBlocking {
        val result = converter.convert("100 f to c")
        assertTrue(result?.startsWith("37.777") == true)
        assertTrue(result?.endsWith("°C") == true)
    }

    @Test
    fun convert_invalidExpression_returnsNull() = runBlocking {
        val result = converter.convert("bonjour le monde")
        assertEquals(null, result)
    }
}
