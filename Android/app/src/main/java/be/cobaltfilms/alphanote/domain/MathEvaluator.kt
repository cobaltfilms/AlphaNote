package be.cobaltfilms.alphanote.domain

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Évaluateur arithmétique sûr (descente récursive). Port fidèle de
 * Evaluation/MathEvaluator.swift (macOS).
 *
 * Supporte : + - * / ^, parenthèses, pourcentage familier (« 50% of 200 »,
 * « 100 - 20% »), factorielle `5!`, fonctions usuelles, la constante `pi`/`π`,
 * la multiplication implicite (`2(3+4)`, `3 pi`) et la virgule décimale.
 * Les mots inconnus (« 5 pommes + 3 ») sont ignorés ; un mot inconnu suivi
 * d'une parenthèse est une fonction inconnue → l'expression est rejetée.
 */
class MathEvaluator {

    fun evaluate(expression: String): Double? {
        val tokens = tokenize(normalize(expression))
        if (tokens.isEmpty()) return null
        val pos = IntRef(0)
        return try {
            val result = parseExpression(tokens, pos)
            if (pos.value == tokens.size && result.isFinite()) result else null
        } catch (_: Exception) {
            null
        }
    }

    // ---- Jetons ----

    private sealed class Token {
        data class Number(val value: Double, val percent: Boolean = false) : Token()
        data object Percent : Token()
        data object Factorial : Token()
        data class Operator(val op: String) : Token()
        data object LParen : Token()
        data object RParen : Token()
        data object Comma : Token()
        data class Identifier(val name: String) : Token()
    }

    private class IntRef(var value: Int)

    private class ParseException : Exception()

    private fun normalize(input: String): String {
        var expression = input
            .replace("÷", "/")
            .replace("×", "*")
            .replace("**", "^")
            .replace("−", "-")
        expression = DECIMAL_COMMA.replace(expression, ".")
        expression = IMPLICIT_X.replace(expression, "*")
        return expression
    }

    private fun tokenize(input: String): List<Token> {
        val raw = mutableListOf<Token>()
        val number = StringBuilder()
        val word = StringBuilder()

        fun flushNumber() {
            if (number.isNotEmpty()) number.toString().toDoubleOrNull()?.let { raw.add(Token.Number(it)) }
            number.setLength(0)
        }

        fun flushWord() {
            if (word.isNotEmpty()) raw.add(Token.Identifier(word.toString().lowercase()))
            word.setLength(0)
        }

        for (ch in input) {
            if (ch.isDigit() || ch == '.') {
                flushWord(); number.append(ch); continue
            }
            if (ch.isLetter() || ch == '_' || ch == 'π') {
                flushNumber(); word.append(ch); continue
            }
            flushNumber(); flushWord()
            when (ch) {
                '%' -> raw.add(Token.Percent)
                '!' -> raw.add(Token.Factorial)
                '+', '*', '/', '^' -> raw.add(Token.Operator(ch.toString()))
                '-' -> raw.add(Token.Operator("-"))
                '(' -> raw.add(Token.LParen)
                ')' -> raw.add(Token.RParen)
                ',', ';' -> raw.add(Token.Comma)
                else -> Unit // espaces, symboles monétaires, etc.
            }
        }
        flushNumber(); flushWord()

        val cleaned = mutableListOf<Token>()
        raw.forEachIndexed { index, token ->
            if (token !is Token.Identifier) { cleaned.add(token); return@forEachIndexed }
            val name = token.name
            when {
                name == "of" -> cleaned.add(Token.Operator("*"))
                FUNCTIONS.containsKey(name) || CONSTANTS.containsKey(name) -> cleaned.add(token)
                index + 1 < raw.size && raw[index + 1] == Token.LParen -> cleaned.add(token) // fonction inconnue → échec
                else -> Unit // mot ignoré
            }
        }

        val final = mutableListOf<Token>()
        var index = 0
        while (index < cleaned.size) {
            val token = cleaned[index]
            if (token is Token.Percent) {
                val last = final.lastOrNull()
                if (last is Token.Number) final[final.lastIndex] = Token.Number(last.value / 100, percent = true)
                if (index + 1 < cleaned.size) {
                    when (cleaned[index + 1]) {
                        is Token.Number, Token.LParen -> final.add(Token.Operator("*"))
                        else -> Unit
                    }
                }
            } else {
                final.add(token)
            }
            index++
        }
        return final
    }

    // ---- Analyse ----

    private fun parseExpression(tokens: List<Token>, pos: IntRef): Double {
        var result = parseTerm(tokens, pos)
        while (pos.value < tokens.size) {
            val t = tokens[pos.value]
            if (t is Token.Operator && (t.op == "+" || t.op == "-")) {
                pos.value++
                val rhsStart = pos.value
                val rhs = parseTerm(tokens, pos)
                // « 100 - 20% » : un pourcentage seul à droite de + / - est relatif.
                val relative = pos.value == rhsStart + 1 && (tokens[rhsStart] as? Token.Number)?.percent == true
                val delta = if (relative) result * rhs else rhs
                result = if (t.op == "+") result + delta else result - delta
            } else break
        }
        return result
    }

    private fun parseTerm(tokens: List<Token>, pos: IntRef): Double {
        var result = parsePower(tokens, pos)
        while (pos.value < tokens.size) {
            val t = tokens[pos.value]
            if (t is Token.Operator && (t.op == "*" || t.op == "/")) {
                pos.value++
                val rhs = parsePower(tokens, pos)
                result = if (t.op == "*") result * rhs else result / rhs
            } else if (t == Token.LParen || t is Token.Identifier) {
                result *= parsePower(tokens, pos) // multiplication implicite
            } else break
        }
        return result
    }

    private fun parsePower(tokens: List<Token>, pos: IntRef): Double {
        val base = parseUnary(tokens, pos)
        if (pos.value < tokens.size) {
            val t = tokens[pos.value]
            if (t is Token.Operator && t.op == "^") {
                pos.value++
                return base.pow(parsePower(tokens, pos))
            }
        }
        return base
    }

    private fun parseUnary(tokens: List<Token>, pos: IntRef): Double {
        if (pos.value < tokens.size) {
            val t = tokens[pos.value]
            if (t is Token.Operator && t.op == "-") { pos.value++; return -parseUnary(tokens, pos) }
            if (t is Token.Operator && t.op == "+") { pos.value++; return parseUnary(tokens, pos) }
        }
        return parsePostfix(tokens, pos)
    }

    private fun parsePostfix(tokens: List<Token>, pos: IntRef): Double {
        var value = parsePrimary(tokens, pos)
        while (pos.value < tokens.size && tokens[pos.value] == Token.Factorial) {
            pos.value++
            value = factorial(value)
        }
        return value
    }

    private fun parsePrimary(tokens: List<Token>, pos: IntRef): Double {
        if (pos.value >= tokens.size) throw ParseException()
        return when (val t = tokens[pos.value]) {
            is Token.Number -> { pos.value++; t.value }
            Token.LParen -> {
                pos.value++
                val result = parseExpression(tokens, pos)
                if (pos.value >= tokens.size || tokens[pos.value] != Token.RParen) throw ParseException()
                pos.value++
                result
            }
            is Token.Identifier -> {
                pos.value++
                CONSTANTS[t.name]?.let { return it }
                if (pos.value >= tokens.size || tokens[pos.value] != Token.LParen) throw ParseException()
                pos.value++
                val arguments = mutableListOf<Double>()
                if (pos.value < tokens.size && tokens[pos.value] == Token.RParen) {
                    pos.value++
                } else {
                    while (true) {
                        arguments.add(parseExpression(tokens, pos))
                        if (pos.value >= tokens.size) throw ParseException()
                        if (tokens[pos.value] == Token.Comma) { pos.value++; continue }
                        if (tokens[pos.value] == Token.RParen) { pos.value++; break }
                        throw ParseException()
                    }
                }
                val function = FUNCTIONS[t.name] ?: throw ParseException()
                function(arguments) ?: throw ParseException()
            }
            else -> throw ParseException()
        }
    }

    private fun factorial(value: Double): Double {
        if (value < 0 || value != round(value) || value > 170) throw ParseException()
        var result = 1.0
        var n = 2.0
        while (n <= value) { result *= n; n += 1 }
        return result
    }

    private companion object {
        val DECIMAL_COMMA = Regex("(?<=\\d),(?=\\d)")
        val IMPLICIT_X = Regex("(?<=\\d|\\)|%)\\s*[xX]\\s*(?=\\d|\\(|[A-Za-z_π])")

        val FUNCTIONS: Map<String, (List<Double>) -> Double?> = mapOf(
            "sqrt" to { a -> if (a.size == 1 && a[0] >= 0) sqrt(a[0]) else null },
            "abs" to { a -> if (a.size == 1) abs(a[0]) else null },
            "round" to { a -> if (a.size == 1) round(a[0]) else null },
            "floor" to { a -> if (a.size == 1) floor(a[0]) else null },
            "ceil" to { a -> if (a.size == 1) ceil(a[0]) else null },
            "ln" to { a -> if (a.size == 1 && a[0] > 0) ln(a[0]) else null },
            "log" to { a -> if (a.size == 1 && a[0] > 0) log10(a[0]) else null },
            "log2" to { a -> if (a.size == 1 && a[0] > 0) log2(a[0]) else null },
            "exp" to { a -> if (a.size == 1) exp(a[0]) else null },
            "sin" to { a -> if (a.size == 1) sin(a[0]) else null },
            "cos" to { a -> if (a.size == 1) cos(a[0]) else null },
            "tan" to { a -> if (a.size == 1) tan(a[0]) else null },
            "min" to { a -> a.minOrNull() },
            "max" to { a -> a.maxOrNull() }
        )

        val CONSTANTS: Map<String, Double> = mapOf("pi" to Math.PI, "π" to Math.PI)
    }
}
