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

    private enum class BufferKind {
        NONE,
        NUMBER,
        IDENTIFIER
    }

    // ---- Public API ----

    /**
     * Évalue une expression mathématique.
     * @return Le résultat, ou null si l'expression est invalide.
     */
    fun evaluate(expression: String, variables: Map<String, Double> = emptyMap()): Double? {
        val normalized = normalize(expression)
        val tokens = tokenize(normalized)
        if (tokens.isEmpty()) return null
        val posRef = IntRef(0)
        return try {
            val result = parseExpression(tokens, posRef = posRef, variables = variables)
            if (posRef.value == tokens.size) result else null
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
        var bufferKind = BufferKind.NONE

        fun flushBuffer() {
            if (buffer.isEmpty()) return
            when (bufferKind) {
                BufferKind.NUMBER -> buffer.toDoubleOrNull()?.let { tokens.add(Token.Number(it)) }
                BufferKind.IDENTIFIER -> tokens.add(Token.Identifier(buffer))
                BufferKind.NONE -> {}
            }
            buffer = ""
            bufferKind = BufferKind.NONE
        }

        while (i < input.length) {
            val ch = input[i]
            when {
                ch in '0'..'9' -> {
                    if (bufferKind == BufferKind.NONE) bufferKind = BufferKind.NUMBER
                    buffer += ch
                }
                ch == '.' -> {
                    if (bufferKind == BufferKind.IDENTIFIER) {
                        flushBuffer()
                    }
                    if (bufferKind == BufferKind.NONE) bufferKind = BufferKind.NUMBER
                    buffer += ch
                }
                ch == '%' -> {
                    flushBuffer()
                    tokens.add(Token.Percent)
                }
                ch == '+' || ch == '*' || ch == '/' -> {
                    flushBuffer()
                    tokens.add(Token.Operator(ch.toString()))
                }
                ch == '^' -> {
                    flushBuffer()
                    tokens.add(Token.Operator("^"))
                }
                ch == '-' -> {
                    if (bufferKind == BufferKind.NUMBER || bufferKind == BufferKind.IDENTIFIER) {
                        flushBuffer()
                        tokens.add(Token.Operator("-"))
                    } else if (tokens.isEmpty() || tokens.last().isBinaryOperator || tokens.last() is Token.LParen) {
                        // Nombre négatif
                        bufferKind = BufferKind.NUMBER
                        buffer += ch
                    } else {
                        tokens.add(Token.Operator("-"))
                    }
                }
                ch == '(' -> {
                    flushBuffer()
                    tokens.add(Token.LParen)
                }
                ch == ')' -> {
                    flushBuffer()
                    tokens.add(Token.RParen)
                }
                ch == ' ' || ch == '\t' -> {
                    flushBuffer()
                }
                ch.isLetter() || ch == '_' -> {
                    if (bufferKind == BufferKind.NUMBER) flushBuffer()
                    if (bufferKind == BufferKind.NONE) bufferKind = BufferKind.IDENTIFIER
                    buffer += ch
                }
                else -> {
                    flushBuffer()
                }
            }
            i++
        }

        flushBuffer()

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

    private fun parseExpression(tokens: List<Token>, posRef: IntRef, variables: Map<String, Double>): Double {
        var result = parseTerm(tokens, posRef, variables)

        while (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && (t.op == "+" || t.op == "-")) {
                posRef.value++
                val rhs = parseTerm(tokens, posRef, variables)
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

    private fun parseTerm(tokens: List<Token>, posRef: IntRef, variables: Map<String, Double>): Double {
        var result = parsePower(tokens, posRef, variables)

        while (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && (t.op == "*" || t.op == "/")) {
                posRef.value++
                val rhs = parsePower(tokens, posRef, variables)
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

    private fun parsePower(tokens: List<Token>, posRef: IntRef, variables: Map<String, Double>): Double {
        var result = parseUnary(tokens, posRef, variables)

        if (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && t.op == "^") {
                posRef.value++
                // Right-associative
                val rhs = parsePower(tokens, posRef, variables)
                result = result.pow(rhs)
            }
        }
        return result
    }

    private fun parseUnary(tokens: List<Token>, posRef: IntRef, variables: Map<String, Double>): Double {
        if (posRef.value < tokens.size) {
            val t = tokens[posRef.value]
            if (t is Token.Operator && t.op == "-") {
                posRef.value++
                val value = parsePrimary(tokens, posRef, variables)
                return -value
            }
        }
        return parsePrimary(tokens, posRef, variables)
    }

    private fun parsePrimary(tokens: List<Token>, posRef: IntRef, variables: Map<String, Double>): Double {
        require(posRef.value < tokens.size) { "Fin d'expression inattendue" }

        return when (val t = tokens[posRef.value]) {
            is Token.Number -> {
                posRef.value++
                t.value
            }
            is Token.LParen -> {
                posRef.value++
                val result = parseExpression(tokens, posRef, variables)
                require(posRef.value < tokens.size && tokens[posRef.value] is Token.RParen) {
                    "Parenthèse fermante manquante"
                }
                posRef.value++
                result
            }
            is Token.Identifier -> {
                posRef.value++
                variables[t.name] ?: variables[t.name.lowercase()]
                ?: throw IllegalArgumentException("Variable inconnue: ${t.name}")
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
