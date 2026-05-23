package be.cobaltfilms.alphanote.domain

import kotlin.math.pow

/**
 * Évaluateur mathématique sécurisé — recursive-descent parser.
 * Portage fidèle de Evaluation/MathEvaluator.swift (macOS).
 *
 * Supporte : +, -, *, /, ^, parenthèses, pourcentages (colloquial).
 * Exemples : "2+2" → 4, "50% of 200" → 100, "(3+4)*2" → 14
 */
class MathEvaluator {

    // ---- Token types ----

    private sealed class Token {
        data class Number(val value: Double) : Token()
        data class Operator(val op: String) : Token()
        data object Percent : Token()
        data object LParen : Token()
        data object RParen : Token()
        data class Identifier(val name: String) : Token()

        val isBinaryOperator: Boolean
            get() = this is Operator && op.isNotEmpty()
    }

    // ---- Public API ----

    /**
     * Évalue une expression mathématique.
     * @return Le résultat, ou null si l'expression est invalide.
     */
    fun evaluate(expression: String): Double? {
        val normalized = normalize(expression)
        val tokens = tokenize(normalized)
        if (tokens.isEmpty()) return null
        var pos = 0
        return try {
            val result = parseExpression(tokens, posRef = IntRef(pos))
            if (pos == tokens.size) result else null
        } catch (e: Exception) {
            null
        }
    }

    // ---- Normalisation ----

    private fun normalize(input: String): String {
        var expr = input
            .replace("÷", "/")
            .replace("×", "*")
            .replace("**", "^")

        // Remplacer les 'x' implicites entre un nombre/parenthèse et un nombre/lettre
        // ex: "2x3" → "2*3", "3(4)" → "3*(4)"
        val implicitMulRegex = Regex("(?<=\\d|\\)|%)\\s*[xX]\\s*(?=\\d|\\(|[A-Za-z_])")
        expr = implicitMulRegex.replace(expr, "*")

        return expr
    }

    // ---- Tokenizer ----

    private fun tokenize(input: String): List<Token> {
        val tokens = mutableListOf<Token>()
        var i = 0
        var buffer = ""

        fun flushNumber() {
            buffer.toDoubleOrNull()?.let { tokens.add(Token.Number(it)) }
            buffer = ""
        }

        fun flushIdentifier() {
            if (buffer.isNotEmpty()) {
                tokens.add(Token.Identifier(buffer))
                buffer = ""
            }
        }

        while (i < input.length) {
            val ch = input[i]
            when {
                ch in '0'..'9' || ch == '.' -> {
                    flushIdentifier()
                    buffer += ch
                }
                ch == '%' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                    tokens.add(Token.Percent)
                }
                ch == '+' || ch == '*' || ch == '/' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                    tokens.add(Token.Operator(ch.toString()))
                }
                ch == '^' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                    tokens.add(Token.Operator("^"))
                }
                ch == '-' -> {
                    flushIdentifier()
                    if (buffer.isNotEmpty()) {
                        flushNumber()
                        tokens.add(Token.Operator("-"))
                    } else if (tokens.isEmpty() || tokens.last().isBinaryOperator || tokens.last() is Token.LParen) {
                        // Nombre négatif
                        buffer += ch
                    } else {
                        tokens.add(Token.Operator("-"))
                    }
                }
                ch == '(' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                    tokens.add(Token.LParen)
                }
                ch == ')' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                    tokens.add(Token.RParen)
                }
                ch == ' ' || ch == '\t' -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                }
                ch.isLetter() || ch == '_' -> {
                    if (buffer.isNotEmpty() && buffer[0].isDigit()) flushNumber()
                    buffer += ch
                }
                else -> {
                    if (buffer.isNotEmpty()) flushNumber()
                    flushIdentifier()
                }
            }
            i++
        }

        if (buffer.isNotEmpty()) {
            if (buffer[0].isDigit() || buffer[0] == '.' || buffer[0] == '-') flushNumber()
            else flushIdentifier()
        }

        // Traiter "50% of 200" → convertir "of" en "*"
        val cleaned = mutableListOf<Token>()
        for (j in tokens.indices) {
            val t = tokens[j]
            if (t is Token.Identifier && t.name.lowercase() == "of") {
                cleaned.add(Token.Operator("*"))
            } else {
                cleaned.add(t)
            }
        }

        // Convertir % autonome en diviseur ×100 sur le nombre précédent
        val final = mutableListOf<Token>()
        for (j in cleaned.indices) {
            val t = cleaned[j]
            if (t is Token.Percent) {
                val lastIdx = final.lastIndex
                if (lastIdx >= 0) {
                    val last = final[lastIdx]
                    if (last is Token.Number) {
                        final[lastIdx] = Token.Number(last.value / 100.0)
                    }
                }
                // Insérer * implicite si le token suivant est nombre ou parenthèse
                if (j + 1 < cleaned.size) {
                    when (cleaned[j + 1]) {
                        is Token.Number, is Token.LParen -> {
                            final.add(Token.Operator("*"))
                        }
                        else -> {}
                    }
                }
            } else {
                final.add(t)
            }
        }

        return final
    }

    // ---- Parser (recursive descent, precedence climbing) ----

    /** Référence mutable pour la position (remplace `inout` de Swift) */
    private class IntRef(var value: Int)

    private fun parseExpression(tokens: List<Token>, posRef: IntRef): Double {
        var result = parseTerm(tokens, posRef)

        while (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && (t.op == "+" || t.op == "-")) {
                posRef.value++
                val rhs = parseTerm(tokens, posRef)
                when (t.op) {
                    "+" -> result += rhs
                    "-" -> result -= rhs
                }
            } else {
                break
            }
        }
        return result
    }

    private fun parseTerm(tokens: List<Token>, posRef: IntRef): Double {
        var result = parsePower(tokens, posRef)

        while (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && (t.op == "*" || t.op == "/")) {
                posRef.value++
                val rhs = parsePower(tokens, posRef)
                when (t.op) {
                    "*" -> result *= rhs
                    "/" -> result /= rhs
                }
            } else {
                break
            }
        }
        return result
    }

    private fun parsePower(tokens: List<Token>, posRef: IntRef): Double {
        var result = parseUnary(tokens, posRef)

        if (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && t.op == "^") {
                posRef.value++
                // Right-associative
                val rhs = parsePower(tokens, posRef)
                result = result.pow(rhs)
            }
        }
        return result
    }

    private fun parseUnary(tokens: List<Token>, posRef: IntRef): Double {
        if (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && t.op == "-") {
                posRef.value++
                val value = parsePrimary(tokens, posRef)
                return -value
            }
        }
        return parsePrimary(tokens, posRef)
    }

    private fun parsePrimary(tokens: List<Token>, posRef: IntRef): Double {
        require(posRef.value < tokens.size) { "Fin d'expression inattendue" }

        return when (val t = tokens[posRef.value]) {
            is Token.Number -> {
                posRef.value++
                t.value
            }
            is Token.LParen -> {
                posRef.value++
                val result = parseExpression(tokens, posRef)
                require(posRef.value < tokens.size && tokens[posRef.value] is Token.RParen) {
                    "Parenthèse fermante manquante"
                }
                posRef.value++
                result
            }
            is Token.Identifier -> {
                posRef.value++
                // Futur : lookup de variables
                0.0
            }
            else -> throw IllegalArgumentException("Token inattendu : $t")
        }
    }

    enum class ParseError {
        UNEXPECTED_END,
        MISSING_PAREN,
        UNEXPECTED_TOKEN
    }
}
