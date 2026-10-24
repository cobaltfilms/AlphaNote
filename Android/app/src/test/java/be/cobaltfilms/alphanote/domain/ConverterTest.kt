package be.cobaltfilms.alphanote.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConverterTest {
    private val rates = CurrencyRateService(persists = false)
    private val converter = Converter(rates)

    @Test fun lengthConversion() = assertEquals("1000 m", converter.convert("1 km to m"))
    @Test fun temperatureUsesOffset() = assertEquals("86 °F", converter.convert("30 c to f"))
    @Test fun fahrenheitToCelsius() {
        val result = converter.convert("100 f to c")
        assertTrue(result?.startsWith("37.7778") == true)
        assertTrue(result?.endsWith("°C") == true)
    }
    @Test fun durationConversion() = assertEquals("120 min", converter.convert("2 h to min"))
    @Test fun invalidExpression() = assertNull(converter.convert("bonjour le monde"))
    @Test fun currencyUsesCachedRatesOnly() {
        assertNull(converter.convert("100 usd to eur"))
        rates.seed("USD", mapOf("EUR" to 0.92))
        assertEquals("92 EUR", converter.convert("100 usd to eur"))
        assertEquals("92 EUR", converter.convert("$100 to EUR"))
    }
    @Test fun currencyProviderParsing() {
        val frankfurter = CurrencyRateService.PROVIDERS[0].parse("""{"base":"EUR","rates":{"USD":1.08}}""")
        assertEquals(1.08, frankfurter!!["USD"]!!, 1e-9)
        val erapi = CurrencyRateService.PROVIDERS[1].parse("""{"result":"success","rates":{"USD":1.08}}""")
        assertEquals(1.08, erapi!!["USD"]!!, 1e-9)
        assertNull(CurrencyRateService.PROVIDERS[1].parse("""{"result":"error"}"""))
    }
}
