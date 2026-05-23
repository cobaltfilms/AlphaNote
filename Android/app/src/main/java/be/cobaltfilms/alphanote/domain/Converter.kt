package be.cobaltfilms.alphanote.domain

import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Convertisseur d'unités et de devises.
 * Portage fidèle de Evaluation/Converter.swift (macOS).
 *
 * Supporte :
 * - Distances (m, km, mi, ft, in...)
 * - Aires (m², ha, acre...)
 * - Volumes (L, gal, m³...)
 * - Masses (kg, lb, oz...)
 * - Températures (°C, °F, K)
 * - Devises (via l'API exchangerate.host)
 *
 * Exemples : "12 km to mi", "100 USD to EUR", "30°C to °F"
 */
class Converter {

    // ---- API Publique ----

    /**
     * Convertit une expression en langage naturel.
     * Format : "<valeur> <unité> to|in|en <unité_cible>"
     * @return Le résultat formaté, ou null si non convertible.
     */
    suspend fun convert(expression: String): String? = withContext(Dispatchers.IO) {
        val cleaned = expression
            .trim()
            .trimEnd('=')
            .trim()

        val split = splitConversionExpression(cleaned) ?: return@withContext null
        val parse = parseLeftHandValue(split.first) ?: return@withContext null
        val toRaw = normalizeToken(split.second)

        convertUnit(parse.value, parse.unit, toRaw)
            ?: convertCurrency(parse.value, parse.currency, toRaw)
    }

    // ---- Parsing ----

    private data class SplitResult(val left: String, val right: String)
    private data class ParseValue(val value: Double, val unit: String, val currency: String)

    private fun splitConversionExpression(expression: String): Pair<String, String>? {
        val regex = Regex("(?i)\\s+(to|in|en)\\s+")
        val match = regex.find(expression) ?: return null

        val left = expression.substring(0, match.range.first).trim()
        val right = expression.substring(match.range.last + 1).trim()

        if (left.isEmpty() || right.isEmpty()) return null
        return Pair(left, right)
    }

    private fun parseLeftHandValue(left: String): ParseValue? {
        val numberPattern = Regex("[-+]?\\d+(?:[.,]\\d+)?")
        val numberMatch = numberPattern.find(left) ?: return null

        val numberText = numberMatch.value.replace(",", ".")
        val value = numberText.toDoubleOrNull() ?: return null

        val before = left.substring(0, numberMatch.range.first).trim()
        val afterStart = numberMatch.range.last + 1
        val after = if (afterStart < left.length) left.substring(afterStart).trim() else ""

        val symbolCurrency = currencyFromSymbol(before.ifEmpty { after })
        val fromCurrency = if (symbolCurrency.isNotEmpty()) symbolCurrency
            else normalizeCurrency(before.ifEmpty { after })
        val fromUnitRaw = normalizeToken(after.ifEmpty { before })

        return ParseValue(value, fromUnitRaw, fromCurrency)
    }

    // ---- Conversion d'unités ----

    private fun convertUnit(value: Double, from: String, to: String): String? {
        // Chaque catégorie teste from et to dans le même espace
        val categories = listOf(
            ::lengthUnit, ::areaUnit, ::volumeUnit, ::massUnit, ::temperatureUnit
        )

        for (categoryFn in categories) {
            val fromUnit = categoryFn(from) ?: continue
            val toUnit = categoryFn(to) ?: continue
            val converted = convertDimension(value, fromUnit, toUnit)
            return formatResult(converted, to)
        }

        return null
    }

    /**
     * Facteur de conversion générique pour les unités du même type.
     * Chaque unité définit son ratio vers une unité de base.
     */
    private fun convertDimension(value: Double, from: UnitDef, to: UnitDef): Double {
        val base = value * from.toBase
        return base / to.toBase
    }

    // ---- Définitions des unités ----

    /** Représente une unité avec son facteur vers l'unité de base de sa catégorie */
    private data class UnitDef(val symbol: String, val toBase: Double)

    // Distances — base : mètre
    private fun lengthUnit(raw: String): UnitDef? = lengthMap[normalizeToken(raw)]

    private val lengthMap = mapOf(
        "m" to UnitDef("m", 1.0),
        "meter" to UnitDef("m", 1.0), "metre" to UnitDef("m", 1.0),
        "meters" to UnitDef("m", 1.0), "metres" to UnitDef("m", 1.0),
        "cm" to UnitDef("cm", 0.01), "centimeter" to UnitDef("cm", 0.01),
        "centimetre" to UnitDef("cm", 0.01), "centimeters" to UnitDef("cm", 0.01),
        "mm" to UnitDef("mm", 0.001), "millimeter" to UnitDef("mm", 0.001),
        "km" to UnitDef("km", 1000.0), "kilometer" to UnitDef("km", 1000.0),
        "in" to UnitDef("in", 0.0254), "inch" to UnitDef("in", 0.0254),
        "inches" to UnitDef("in", 0.0254), "\"" to UnitDef("in", 0.0254),
        "ft" to UnitDef("ft", 0.3048), "foot" to UnitDef("ft", 0.3048),
        "feet" to UnitDef("ft", 0.3048), "'" to UnitDef("ft", 0.3048),
        "mi" to UnitDef("mi", 1609.344), "mile" to UnitDef("mi", 1609.344),
        "miles" to UnitDef("mi", 1609.344),
        "yd" to UnitDef("yd", 0.9144), "yard" to UnitDef("yd", 0.9144),
        "yards" to UnitDef("yd", 0.9144)
    )

    // Aires — base : m²
    private fun areaUnit(raw: String): UnitDef? = areaMap[normalizeToken(raw)]

    private val areaMap = mapOf(
        "sqm" to UnitDef("m²", 1.0), "m²" to UnitDef("m²", 1.0),
        "sqmeters" to UnitDef("m²", 1.0), "squaremeter" to UnitDef("m²", 1.0),
        "sqcm" to UnitDef("cm²", 0.0001), "cm²" to UnitDef("cm²", 0.0001),
        "ha" to UnitDef("ha", 10000.0), "hectare" to UnitDef("ha", 10000.0),
        "sqkm" to UnitDef("km²", 1_000_000.0), "km²" to UnitDef("km²", 1_000_000.0),
        "sqft" to UnitDef("ft²", 0.09290304), "ft²" to UnitDef("ft²", 0.09290304),
        "sqin" to UnitDef("in²", 0.00064516), "in²" to UnitDef("in²", 0.00064516),
        "sqmi" to UnitDef("mi²", 2_589_988.11), "mi²" to UnitDef("mi²", 2_589_988.11),
        "acre" to UnitDef("acre", 4046.85642), "acres" to UnitDef("acre", 4046.85642),
        "are" to UnitDef("are", 100.0), "ares" to UnitDef("are", 100.0)
    )

    // Volumes — base : litre
    private fun volumeUnit(raw: String): UnitDef? = volumeMap[normalizeToken(raw)]

    private val volumeMap = mapOf(
        "l" to UnitDef("L", 1.0), "liter" to UnitDef("L", 1.0),
        "litre" to UnitDef("L", 1.0), "liters" to UnitDef("L", 1.0),
        "ml" to UnitDef("mL", 0.001), "milliliter" to UnitDef("mL", 0.001),
        "m³" to UnitDef("m³", 1000.0), "cubicmeter" to UnitDef("m³", 1000.0),
        "cm³" to UnitDef("cm³", 0.001), "cc" to UnitDef("cm³", 0.001),
        "gal" to UnitDef("gal", 3.78541), "gallon" to UnitDef("gal", 3.78541),
        "qt" to UnitDef("qt", 0.946353), "quart" to UnitDef("qt", 0.946353),
        "pt" to UnitDef("pt", 0.473176), "pint" to UnitDef("pt", 0.473176),
        "cup" to UnitDef("cup", 0.236588), "cups" to UnitDef("cup", 0.236588),
        "floz" to UnitDef("floz", 0.0295735), "fluidounce" to UnitDef("floz", 0.0295735),
        "tbsp" to UnitDef("tbsp", 0.0147868), "tablespoon" to UnitDef("tbsp", 0.0147868),
        "tsp" to UnitDef("tsp", 0.00492892), "teaspoon" to UnitDef("tsp", 0.00492892)
    )

    // Masses — base : kg
    private fun massUnit(raw: String): UnitDef? = massMap[normalizeToken(raw)]

    private val massMap = mapOf(
        "kg" to UnitDef("kg", 1.0), "kilogram" to UnitDef("kg", 1.0),
        "kilograms" to UnitDef("kg", 1.0),
        "g" to UnitDef("g", 0.001), "gram" to UnitDef("g", 0.001),
        "grams" to UnitDef("g", 0.001),
        "mg" to UnitDef("mg", 0.000001), "milligram" to UnitDef("mg", 0.000001),
        "t" to UnitDef("t", 1000.0), "tonne" to UnitDef("t", 1000.0),
        "metricton" to UnitDef("t", 1000.0),
        "lb" to UnitDef("lb", 0.453592), "lbs" to UnitDef("lb", 0.453592),
        "pound" to UnitDef("lb", 0.453592), "pounds" to UnitDef("lb", 0.453592),
        "oz" to UnitDef("oz", 0.0283495), "ounce" to UnitDef("oz", 0.0283495),
        "ounces" to UnitDef("oz", 0.0283495),
        "st" to UnitDef("st", 6.35029), "stone" to UnitDef("st", 6.35029),
        "stones" to UnitDef("st", 6.35029)
    )

    // Températures — base : Kelvin (pour les conversions relatives)
    // Note : les températures utilisent un offset, pas un simple ratio.
    private fun temperatureUnit(raw: String): UnitDef? = temperatureMap[normalizeToken(raw)]

    private val temperatureMap = mapOf(
        "c" to UnitDef("°C", 1.0), "°c" to UnitDef("°C", 1.0),
        "celsius" to UnitDef("°C", 1.0), "centigrade" to UnitDef("°C", 1.0),
        "f" to UnitDef("°F", 1.0), "°f" to UnitDef("°F", 1.0),
        "fahrenheit" to UnitDef("°F", 1.0),
        "k" to UnitDef("K", 1.0), "kelvin" to UnitDef("K", 1.0),
        "kelvins" to UnitDef("K", 1.0)
    )

    // Redéfinition pour les températures (conversion avec offset)
    private fun convertUnit(value: Double, from: String, to: String, isTemperature: Boolean): String? {
        return when {
            isTemperature -> convertTemperature(value, from, to)
            else -> null
        }
    }

    private fun convertTemperature(value: Double, fromRaw: String, toRaw: String): String? {
        val from = normalizeToken(fromRaw)
        val to = normalizeToken(toRaw)

        // Vers Kelvin d'abord
        val kelvin = when (from) {
            "c", "°c", "celsius", "centigrade" -> value + 273.15
            "f", "°f", "fahrenheit" -> (value - 32) * 5.0 / 9.0 + 273.15
            "k", "kelvin", "kelvins" -> value
            else -> return null
        }

        val result = when (to) {
            "c", "°c", "celsius", "centigrade" -> kelvin - 273.15
            "f", "°f", "fahrenheit" -> (kelvin - 273.15) * 9.0 / 5.0 + 32
            "k", "kelvin", "kelvins" -> kelvin
            else -> return null
        }
        return formatResult(result, to)
    }

    // ---- Conversion de devises ----

    private var cachedRates: Map<String, Double> = emptyMap()
    private var ratesBase: String = ""
    private var ratesTimestamp: Long = 0L

    private suspend fun convertCurrency(value: Double, from: String, to: String): String? {
        if (from.length != 3 || !from.all { it.isUpperCase() }) return null
        if (to.length != 3 || !to.all { it.isUpperCase() }) return null

        val rates = fetchRates(from)
        val rate = rates[to] ?: return null
        val converted = value * rate
        return "${formatNumber(converted)} $to"
    }

    private suspend fun fetchRates(base: String): Map<String, Double> {
        val now = System.currentTimeMillis()
        // Cache valide 1 heure
        if (ratesBase == base && (now - ratesTimestamp) < 3_600_000 && cachedRates.isNotEmpty()) {
            return cachedRates
        }

        return try {
            val client = OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .build()

            val request = Request.Builder()
                .url("https://api.exchangerate.host/latest?base=$base")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return emptyMap()

            val json = JSONObject(body)
            val ratesObj = json.optJSONObject("rates") ?: return emptyMap()

            val rates = mutableMapOf<String, Double>()
            ratesObj.keys().forEach { key ->
                rates[key] = ratesObj.getDouble(key)
            }

            cachedRates = rates
            ratesBase = base
            ratesTimestamp = now
            rates
        } catch (e: IOException) {
            emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    // ---- Helpers ----

    private fun currencyFromSymbol(token: String): String {
        return when (token.trim()) {
            "$" -> "USD"
            "€" -> "EUR"
            "£" -> "GBP"
            "¥", "￥" -> "JPY"
            else -> ""
        }
    }

    private fun normalizeCurrency(token: String): String {
        val value = token.trim().uppercase()
        return if (value.length == 3 && value.all { it.isLetter() }) value else ""
    }

    private fun normalizeToken(token: String): String {
        return token
            .lowercase()
            .trim()
            .replace("°", "")
            .replace(" ", "")
    }

    private fun formatResult(value: Double, unit: String): String {
        return "${formatNumber(value)} $unit"
    }

    private fun formatNumber(value: Double): String {
        if (value == value.toLong().toDouble()) {
            return value.toLong().toString()
        }
        var formatted = "%.6f".format(value)
        while (formatted.endsWith('0')) {
            formatted = formatted.dropLast(1)
        }
        if (formatted.endsWith('.')) {
            formatted = formatted.dropLast(1)
        }
        return formatted
    }
}
