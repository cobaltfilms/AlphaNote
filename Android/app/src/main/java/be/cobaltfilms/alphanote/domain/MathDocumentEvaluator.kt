package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.model.Note

/**
 * Évalue une note en mode `math` ligne par ligne : variables (`nom: expr`),
 * résultats inline (`expr =`), unités et devises, pourcentages relatifs.
 * Port de Evaluation/MathDocumentEvaluator.swift — logique pure, testable.
 */
class MathDocumentEvaluator(private val converter: Converter = Converter()) {

    data class LineOutcome(val index: Int, val original: String, val transformed: String) {
        val changed: Boolean get() = original != transformed
    }

    data class Assignment(val name: String, val expression: String, val showsResult: Boolean)

    data class Result(val display: String, val numericValue: Double?, val unitHint: String?, val isError: Boolean = false)

    private val evaluator = MathEvaluator()

    fun evaluate(content: String): List<LineOutcome> {
        val lines = content.split("\n")
        val variables = mutableMapOf<String, Double>()
        val variableUnits = mutableMapOf<String, String>()
        val percentVariables = mutableSetOf<String>()
        val outcomes = mutableListOf<LineOutcome>()

        lines.forEachIndexed { index, line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("//") || (index == 0 && isMathHeader(trimmed))) {
                outcomes.add(LineOutcome(index, line, line)); return@forEachIndexed
            }

            val assignment = parseVariableAssignment(line)
            if (assignment != null) {
                val result = evaluateExpression(assignment.expression, variables, variableUnits, percentVariables)
                val numeric = result?.numericValue
                if (result != null && numeric != null) {
                    variables[assignment.name] = numeric
                    val key = assignment.name.lowercase()
                    val isRatioPercent = shouldTreatAsUnitlessRatio(assignment.expression, variableUnits)
                    if (assignment.expression.contains("%") || isRatioPercent) percentVariables.add(key) else percentVariables.remove(key)
                    val hint = result.unitHint
                    if (hint != null) variableUnits[assignment.name] = hint else variableUnits.remove(assignment.name)

                    if (assignment.showsResult) {
                        val prefix = line.substringBefore('=').trim()
                        outcomes.add(LineOutcome(index, line, "$prefix = ${result.display}"))
                        return@forEachIndexed
                    }
                }
                outcomes.add(LineOutcome(index, line, line))
                return@forEachIndexed
            }

            val equalIndex = line.indexOf('=')
            if (equalIndex >= 0) {
                val lhs = line.substring(0, equalIndex).trim()
                if (lhs.isEmpty()) { outcomes.add(LineOutcome(index, line, line)); return@forEachIndexed }
                val result = evaluateExpression(
                    lhs, variables, variableUnits, percentVariables,
                    forcePercentOutput = percentVariables.contains(lhs.lowercase())
                )
                outcomes.add(LineOutcome(index, line, if (result != null) "$lhs = ${result.display}" else "$lhs ="))
                return@forEachIndexed
            }

            outcomes.add(LineOutcome(index, line, line))
        }
        return outcomes
    }

    fun transformed(content: String): String = evaluate(content).joinToString("\n") { it.transformed }

    /** Noms de variables définis dans la note (pour la coloration). */
    fun variableNames(content: String): Set<String> {
        val names = mutableSetOf<String>()
        content.split("\n").forEachIndexed { index, line ->
            if (index == 0 && isMathHeader(line.trim())) return@forEachIndexed
            parseVariableAssignment(line)?.let { names.add(it.name) }
        }
        return names
    }

    // ---- Évaluation d'une expression ----

    fun evaluateExpression(
        expression: String,
        variables: Map<String, Double> = emptyMap(),
        variableUnits: Map<String, String> = emptyMap(),
        percentVariables: Set<String> = emptySet(),
        forcePercentOutput: Boolean = false
    ): Result? {
        val expanded = expandRelativePercentVariables(expression, percentVariables)
        val substituted = substituteVariables(expanded, variables)

        converter.convert(substituted)?.let { converted ->
            return Result(converted, extractLeadingNumber(converted), extractTrailingUnitHint(converted))
        }
        if (looksLikeCurrencyConversion(substituted)) {
            return Result("…", null, null) // taux pas encore chargé
        }

        val explicitOrdered = detectExplicitUnitHints(expression)
        val inferred = inferVariableUnitHints(expression, variableUnits)
        val combined = explicitOrdered.toSet() + inferred
        val preferred = explicitOrdered.firstOrNull() ?: inferred.firstOrNull()
        var unitHint = resolveCompatibleUnitHint(combined, preferred)
        if (shouldTreatAsUnitlessRatio(expression, variableUnits)) unitHint = null
        if (combined.size > 1 && unitHint == null) {
            return Result("⚠︎ unités incompatibles", null, null, isError = true)
        }

        val normalized = normalizeUnitLiterals(substituted, unitHint)
        val value = evaluator.evaluate(sanitize(normalized)) ?: return null
        val display = if (forcePercentOutput) "${format(value * 100)}%" else formatWithUnit(value, unitHint)
        return Result(display, value, unitHint)
    }

    // ---- Variables ----

    private fun substituteVariables(expression: String, variables: Map<String, Double>): String {
        var resolved = expression
        for (name in variables.keys.sortedByDescending { it.length }) {
            val value = variables[name] ?: continue
            val escaped = Regex.escape(name)
            val pattern = if (name.any { it.isWhitespace() }) {
                "(?<![\\p{L}\\p{N}_])$escaped(?![\\p{L}\\p{N}_])"
            } else {
                "(?<![\\p{L}\\p{N}_])$escaped(?![\\p{L}\\p{N}_]|\\s+[\\p{L}_])"
            }
            val regex = runCatching { Regex(pattern, RegexOption.IGNORE_CASE) }.getOrNull() ?: continue
            resolved = regex.replace(resolved, Regex.escapeReplacement(value.toString()))
        }
        return resolved
    }

    private fun expandRelativePercentVariables(expression: String, percentVariables: Set<String>): String {
        if (percentVariables.isEmpty()) return expression
        val (terms, operators) = splitTopLevelAddSub(expression)
        if (operators.isEmpty()) return expression
        var result = terms[0]
        operators.forEachIndexed { index, op ->
            val rhs = terms[index + 1]
            result = if (isPercentVariableTerm(rhs, percentVariables)) "($result $op ($result * $rhs))" else "($result $op $rhs)"
        }
        return result
    }

    private fun splitTopLevelAddSub(expression: String): Pair<List<String>, List<String>> {
        val terms = mutableListOf<String>()
        val operators = mutableListOf<String>()
        var depth = 0
        val current = StringBuilder()
        var previousNonSpace: Char? = null
        for (char in expression) {
            if (char == '(') { depth++; current.append(char); previousNonSpace = char; continue }
            if (char == ')') { depth = maxOf(0, depth - 1); current.append(char); previousNonSpace = char; continue }
            if (depth == 0 && (char == '+' || char == '-')) {
                val isUnary = previousNonSpace == null || "(+-*/^".contains(previousNonSpace!!)
                if (!isUnary) {
                    terms.add(current.toString().trim()); operators.add(char.toString())
                    current.setLength(0); previousNonSpace = null; continue
                }
            }
            current.append(char)
            if (!char.isWhitespace()) previousNonSpace = char
        }
        terms.add(current.toString().trim())
        return terms to operators
    }

    private fun isPercentVariableTerm(term: String, percentVariables: Set<String>): Boolean {
        var candidate = term.trim()
        while (candidate.startsWith("(") && candidate.endsWith(")") && candidate.length >= 2) {
            candidate = candidate.substring(1, candidate.length - 1).trim()
        }
        if (!IDENTIFIER_REGEX.matches(candidate)) return false
        return percentVariables.contains(candidate.lowercase())
    }

    private fun sanitize(expression: String): String = expression
        .replace("€", "").replace("$", "").replace("£", "").replace("¥", "").replace("￥", "")
        .replace(Regex("\\s+"), " ").trim()

    private fun looksLikeCurrencyConversion(expression: String): Boolean = CURRENCY_CONVERSION_REGEX.matches(expression)

    private fun extractLeadingNumber(text: String): Double? =
        NUMBER_REGEX.find(text)?.value?.replace(",", ".")?.toDoubleOrNull()

    // ---- Unités ----

    private fun detectExplicitUnitHints(expression: String): List<String> {
        val hints = mutableListOf<String>()
        for (match in UNIT_LITERAL_REGEX.findAll(expression)) {
            val canonical = Converter.canonicalUnitToken(match.groupValues[2]) ?: continue
            if (canonical !in hints) hints.add(canonical)
        }
        return hints
    }

    private fun variableRegex(name: String): Regex? {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null
        return runCatching { Regex("(?<![\\p{L}\\p{N}_])${Regex.escape(trimmed)}(?![\\p{L}\\p{N}_])", RegexOption.IGNORE_CASE) }.getOrNull()
    }

    private fun inferVariableUnitHints(expression: String, variableUnits: Map<String, String>): Set<String> {
        val hints = mutableSetOf<String>()
        for ((name, unit) in variableUnits) {
            val regex = variableRegex(name) ?: continue
            if (regex.containsMatchIn(expression)) Converter.canonicalUnitToken(unit)?.let { hints.add(it) }
        }
        return hints
    }

    private fun shouldTreatAsUnitlessRatio(expression: String, variableUnits: Map<String, String>): Boolean {
        if (!expression.contains("/")) return false
        val matched = mutableListOf<String>()
        for ((name, unit) in variableUnits) {
            val regex = variableRegex(name) ?: continue
            val canonical = Converter.canonicalUnitToken(unit) ?: continue
            repeat(regex.findAll(expression).count()) { matched.add(canonical) }
        }
        if (matched.size < 2) return false
        return matched.map { Converter.unitFamily(it) }.toSet().size == 1
    }

    private fun extractTrailingUnitHint(text: String): String? {
        val match = TRAILING_UNIT_REGEX.find(text.trim()) ?: return null
        return Converter.canonicalUnitToken(match.groupValues[1])
    }

    private fun resolveCompatibleUnitHint(hints: Set<String>, preferred: String?): String? {
        if (hints.isEmpty()) return null
        if (hints.size == 1) return hints.first()
        val families = hints.map { Converter.unitFamily(it) }
        if (families.any { it == "unknown" } || families.toSet().size != 1) return null
        if (families.first() == "currency" && hints.map { Converter.currencyCode(it) }.toSet().size != 1) return null
        preferred?.let { Converter.canonicalUnitToken(it) }?.let { if (hints.contains(it)) return it }
        return hints.first()
    }

    private fun normalizeUnitLiterals(expression: String, targetUnit: String?): String {
        val target = targetUnit ?: return expression
        val targetFamily = Converter.unitFamily(target)
        if (targetFamily == "unknown") return expression
        var result = expression
        for (match in UNIT_LITERAL_REGEX.findAll(expression).toList().asReversed()) {
            val value = match.groupValues[1].replace(",", ".").toDoubleOrNull() ?: continue
            val source = Converter.canonicalUnitToken(match.groupValues[2]) ?: continue
            if (Converter.unitFamily(source) != targetFamily) continue
            val replacement = if (targetFamily == "currency") {
                if (Converter.currencyCode(source) != Converter.currencyCode(target)) continue
                format(value)
            } else {
                val converted = converter.convertValue(value, source, target) ?: continue
                format(converted)
            }
            result = result.replaceRange(match.range, replacement)
        }
        return result
    }

    // ---- Format ----

    private fun formatWithUnit(value: Double, unitHint: String?): String {
        val number = format(value)
        if (unitHint.isNullOrEmpty()) return number
        if (unitHint in setOf("€", "$", "£", "¥")) return "$number$unitHint"
        return "$number $unitHint"
    }

    companion object {
        private val IDENTIFIER_REGEX = Regex("^[\\p{L}_][\\p{L}\\p{N}_]*$")
        private val VARIABLE_NAME_REGEX = Regex("^[\\p{L}_][\\p{L}\\p{N}_ ]*$")
        private val NUMBER_REGEX = Regex("[-+]?\\d+(?:[.,]\\d+)?")
        private val UNIT_LITERAL_REGEX = Regex("([-+]?\\d+(?:[.,]\\d+)?)\\s*(€|\\$|£|¥|￥|[A-Za-z°²]+)")
        private val TRAILING_UNIT_REGEX = Regex("[-+]?\\d+(?:[.,]\\d+)?\\s*([^0-9\\s]+|[A-Za-z°²]+)$")
        private val CURRENCY_CONVERSION_REGEX = Regex("(?i)^\\s*[-+]?\\d+(?:[.,]\\d+)?\\s*[A-Za-z]{3}\\s+(to|in|en)\\s+[A-Za-z]{3}\\s*=?\\s*$")

        fun isMathHeader(line: String): Boolean {
            val lower = line.lowercase()
            return lower == "math" || lower.startsWith("math:")
        }

        fun isModeKeyword(name: String): Boolean = Note.knownKeywords.contains(name.trim().lowercase())

        fun parseVariableAssignment(line: String): Assignment? {
            val colonIndex = line.indexOf(':')
            if (colonIndex < 0) return null
            val name = line.substring(0, colonIndex).trim()
            if (name.isEmpty() || isModeKeyword(name) || !VARIABLE_NAME_REGEX.matches(name)) return null
            var expression = line.substring(colonIndex + 1).trim()
            var showsResult = false
            val equalIndex = expression.indexOf('=')
            if (equalIndex >= 0) { expression = expression.substring(0, equalIndex).trim(); showsResult = true }
            if (expression.isEmpty()) return null
            return Assignment(name, expression, showsResult)
        }

        fun format(value: Double): String = Converter.formatNumber(value)
    }
}

/**
 * Applique les résultats math au texte de l'éditeur sans réécrire la note :
 * seule la queue après le premier « = » des lignes changées est remplacée.
 * Port de NoteEditorView.applyMathResults (macOS).
 */
object MathInlineApplier {
    data class Outcome(val text: String, val cursor: Int, val changed: Boolean)

    fun apply(text: String, cursor: Int, evaluator: MathDocumentEvaluator, respectCaret: Boolean): Outcome {
        val outcomes = evaluator.evaluate(text).filter { it.changed }
        if (outcomes.isEmpty()) return Outcome(text, cursor, false)

        val lineStarts = mutableListOf(0)
        text.forEachIndexed { index, ch -> if (ch == '\n') lineStarts.add(index + 1) }

        var result = text
        var newCursor = cursor
        var changed = false
        for (outcome in outcomes.asReversed()) {
            if (outcome.index >= lineStarts.size) continue
            val lineStart = lineStarts[outcome.index]
            val equalIndex = outcome.original.indexOf('=')
            if (equalIndex < 0) continue
            val tailStart = lineStart + equalIndex + 1
            val tailEnd = lineStart + outcome.original.length
            if (tailEnd > result.length) continue
            val transformedEqual = outcome.transformed.indexOf('=')
            if (transformedEqual < 0) continue
            val newTail = outcome.transformed.substring(transformedEqual + 1)

            if (respectCaret && tailEnd > tailStart && cursor > tailStart && cursor <= tailEnd) continue

            result = result.replaceRange(tailStart, tailEnd, newTail)
            if (tailStart < newCursor) newCursor += newTail.length - (tailEnd - tailStart)
            changed = true
        }
        return Outcome(result, newCursor.coerceIn(0, result.length), changed)
    }
}
