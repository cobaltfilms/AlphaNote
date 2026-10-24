package be.cobaltfilms.alphanote.domain

import java.util.Locale

/**
 * Conversion d'unités et de devises. Port de Evaluation/Converter.swift.
 * Synchrone : les devises lisent le cache de [CurrencyRateService] et
 * retournent null tant que le taux n'est pas chargé.
 *
 * Exemples : "12 km to mi", "100 USD to EUR", "30°C to °F", "2 h to min"
 */
class Converter(private val rateService: CurrencyRateService = CurrencyRateService.shared) {

    /** Une unité : famille, facteur vers la base, décalage (température). */
    data class UnitDef(val canonical: String, val family: String, val toBase: Double, val offset: Double = 0.0)

    fun convert(expression: String): String? {
        val cleaned = expression.trim().trimEnd('=').trim()
        val (left, right) = splitConversionExpression(cleaned) ?: return null
        val parse = parseLeftHandValue(left) ?: return null
        val toRaw = normalizeToken(right)

        convertUnit(parse.value, parse.unit, toRaw)?.let { return it }
        return convertCurrency(parse.value, parse.currency, toRaw)
    }

    /** Convertit une valeur entre deux unités de la même famille, ou null. */
    fun convertValue(value: Double, fromToken: String, toToken: String): Double? {
        val from = unitDefinition(fromToken) ?: return null
        val to = unitDefinition(toToken) ?: return null
        if (from.family != to.family) return null
        val base = (value + from.offset) * from.toBase
        return base / to.toBase - to.offset
    }

    fun unitDefinition(token: String): UnitDef? {
        val canonical = canonicalUnitToken(token) ?: return null
        return UNITS[canonical]
    }

    // ---- Parsing ----

    private data class ParseValue(val value: Double, val unit: String, val currency: String)

    private fun splitConversionExpression(expression: String): Pair<String, String>? {
        val match = SPLIT_REGEX.find(expression) ?: return null
        val left = expression.substring(0, match.range.first).trim()
        val right = expression.substring(match.range.last + 1).trim()
        if (left.isEmpty() || right.isEmpty()) return null
        return left to right
    }

    private fun parseLeftHandValue(left: String): ParseValue? {
        val numberMatch = NUMBER_REGEX.find(left) ?: return null
        val value = numberMatch.value.replace(",", ".").toDoubleOrNull() ?: return null
        val before = left.substring(0, numberMatch.range.first).trim()
        val after = left.substring(numberMatch.range.last + 1).trim()

        val symbolCurrency = currencyFromSymbol(before.ifEmpty { after })
        val fromCurrency = symbolCurrency.ifEmpty { normalizeCurrency(before.ifEmpty { after }) }
        val fromUnitRaw = normalizeToken(after.ifEmpty { before })
        return ParseValue(value, fromUnitRaw, fromCurrency)
    }

    // ---- Unités ----

    private fun convertUnit(value: Double, from: String, to: String): String? {
        val toDef = unitDefinition(to) ?: return null
        val converted = convertValue(value, from, to) ?: return null
        val display = if (toDef.family == "temperature") toDef.canonical.uppercase().replace("°C", "°C") else to
        return "${formatNumber(converted)} ${temperatureDisplay(toDef) ?: display}"
    }

    private fun temperatureDisplay(def: UnitDef): String? = when (def.canonical) {
        "°c" -> "°C"
        "°f" -> "°F"
        "k" -> "K"
        else -> null
    }

    // ---- Devises ----

    private fun convertCurrency(value: Double, from: String, to: String): String? {
        val fromCode = from.uppercase()
        val toCode = to.uppercase()
        if (fromCode.length != 3 || toCode.length != 3) return null
        if (!fromCode.all { it.isLetter() } || !toCode.all { it.isLetter() }) return null
        if (fromCode == toCode) return null
        val rate = rateService.rate(fromCode, toCode) ?: return null
        return "${formatNumber(value * rate)} $toCode"
    }

    // ---- Helpers ----

    private fun currencyFromSymbol(token: String): String = when (token.trim()) {
        "$" -> "USD"
        "€" -> "EUR"
        "£" -> "GBP"
        "¥", "￥" -> "JPY"
        else -> ""
    }

    private fun normalizeCurrency(token: String): String {
        val value = token.trim().uppercase()
        return if (value.length == 3 && value.all { it.isLetter() }) value else ""
    }

    private fun normalizeToken(token: String): String = token.lowercase().trim().replace(" ", "")

    companion object {
        private val SPLIT_REGEX = Regex("(?i)\\s+(to|in|en)\\s+")
        private val NUMBER_REGEX = Regex("[-+]?\\d+(?:[.,]\\d+)?")

        fun formatNumber(value: Double): String {
            if (!value.isFinite()) return value.toString()
            if (value == Math.floor(value) && Math.abs(value) < 1e15) return value.toLong().toString()
            var formatted = String.format(Locale.US, "%.4f", value)
            while (formatted.endsWith('0')) formatted = formatted.dropLast(1)
            if (formatted.endsWith('.')) formatted = formatted.dropLast(1)
            return formatted
        }

        /** Jeton canonique d'une unité (ou devise), null si inconnu. */
        fun canonicalUnitToken(rawToken: String): String? {
            val token = rawToken.trim()
            if (token.isEmpty()) return null
            when (token) {
                "￥" -> return "¥"
                "€", "$", "£", "¥" -> return token
            }
            return when (token.lowercase()) {
                "usd", "eur", "gbp", "jpy", "chf", "cad" -> token.lowercase()
                "mm", "millimeter", "millimetre", "millimeters", "millimetres" -> "mm"
                "cm", "centimeter", "centimetre", "centimeters", "centimetres" -> "cm"
                "m", "meter", "metre", "meters", "metres" -> "m"
                "km", "kilometer", "kilometre", "kilometers", "kilometres" -> "km"
                "in", "inch", "inches", "\"", "″" -> "in"
                "ft", "foot", "feet", "'", "′" -> "ft"
                "yd", "yard", "yards" -> "yd"
                "mi", "mile", "miles" -> "mi"
                "mm²", "sqmm", "squaremillimeter", "squaremillimeters", "squaremm" -> "mm2"
                "cm²", "sqcm", "squarecentimeter", "squarecentimeters", "squarecm" -> "cm2"
                "m²", "sqm", "sqmeter", "sqmeters", "squaremeter", "squaremeters", "squarem" -> "m2"
                "km²", "sqkm", "squarekilometer", "squarekilometers", "squarekm" -> "km2"
                "ft²", "sqft", "squarefoot", "squarefeet", "squareft" -> "ft2"
                "in²", "sqin", "squareinch", "squareinches", "squarein" -> "in2"
                "yd²", "sqyd", "squareyard", "squareyards", "squareyd" -> "yd2"
                "mi²", "sqmi", "squaremile", "squaremiles", "squaremi" -> "mi2"
                "ha", "hectare", "hectares" -> "ha"
                "acre", "acres" -> "acre"
                "are", "ares" -> "are"
                "ml", "milliliter", "millilitre", "milliliters", "millilitres" -> "ml"
                "l", "liter", "litre", "liters", "litres" -> "l"
                "cl", "centiliter", "centilitre", "centiliters", "centilitres" -> "cl"
                "gal", "gallon", "gallons" -> "gal"
                "qt", "quart", "quarts" -> "qt"
                "pt", "pint", "pints" -> "pt"
                "cup", "cups" -> "cup"
                "mg", "milligram", "milligrams", "mgs" -> "mg"
                "g", "gram", "grams", "gs" -> "g"
                "kg", "kilogram", "kilograms", "kgs" -> "kg"
                "t", "tonne", "tonnes" -> "t"
                "lb", "lbs", "pound", "pounds" -> "lb"
                "oz", "ozs", "ounce", "ounces" -> "oz"
                "c", "°c", "celsius", "centigrade" -> "°c"
                "f", "°f", "fahrenheit" -> "°f"
                "k", "kelvin", "kelvins" -> "k"
                "s", "sec", "secs", "second", "seconds" -> "s"
                "min", "mins", "mn", "minute", "minutes" -> "min"
                "h", "hr", "hrs", "hour", "hours" -> "h"
                else -> null
            }
        }

        fun unitFamily(canonical: String): String = UNITS[canonical]?.family
            ?: if (canonical in setOf("$", "€", "£", "¥", "usd", "eur", "gbp", "jpy", "chf", "cad")) "currency" else "unknown"

        fun currencyCode(unit: String): String = when (unit.lowercase()) {
            "€", "eur" -> "eur"
            "$", "usd" -> "usd"
            "£", "gbp" -> "gbp"
            "¥", "jpy" -> "jpy"
            else -> unit.lowercase()
        }

        private fun u(c: String, family: String, toBase: Double, offset: Double = 0.0) = c to UnitDef(c, family, toBase, offset)

        /** Bases : m, m², L, kg, kelvin (avec décalage), s. */
        val UNITS: Map<String, UnitDef> = mapOf(
            u("mm", "length", 0.001), u("cm", "length", 0.01), u("m", "length", 1.0), u("km", "length", 1000.0),
            u("in", "length", 0.0254), u("ft", "length", 0.3048), u("yd", "length", 0.9144), u("mi", "length", 1609.344),
            u("mm2", "area", 1e-6), u("cm2", "area", 1e-4), u("m2", "area", 1.0), u("km2", "area", 1e6),
            u("ft2", "area", 0.09290304), u("in2", "area", 0.00064516), u("yd2", "area", 0.83612736),
            u("mi2", "area", 2_589_988.110336), u("ha", "area", 10_000.0), u("acre", "area", 4046.8564224), u("are", "area", 100.0),
            u("ml", "volume", 0.001), u("cl", "volume", 0.01), u("l", "volume", 1.0), u("gal", "volume", 3.785411784),
            u("qt", "volume", 0.946352946), u("pt", "volume", 0.473176473), u("cup", "volume", 0.2365882365),
            u("mg", "mass", 1e-6), u("g", "mass", 0.001), u("kg", "mass", 1.0), u("t", "mass", 1000.0),
            u("lb", "mass", 0.45359237), u("oz", "mass", 0.028349523125),
            // Température : base kelvin. (v + offset) * toBase = K.
            u("°c", "temperature", 1.0, 273.15), u("°f", "temperature", 5.0 / 9.0, 459.67), u("k", "temperature", 1.0, 0.0),
            u("s", "duration", 1.0), u("min", "duration", 60.0), u("h", "duration", 3600.0)
        )
    }
}
