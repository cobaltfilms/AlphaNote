import Foundation

/// Évalue une note en mode `math` ligne par ligne : variables (`nom: expr`),
/// résultats inline (`expr =`), unités et devises, pourcentages relatifs.
/// Logique pure, sans AppKit, testable : l'éditeur ne fait que comparer les
/// lignes transformées aux lignes d'origine et remplacer celles qui changent.
struct MathDocumentEvaluator {
    struct LineOutcome: Equatable {
        let index: Int
        let original: String
        let transformed: String
        var changed: Bool { original != transformed }
    }

    private let evaluator = MathEvaluator()
    private let converter: Converter

    init(converter: Converter = Converter()) {
        self.converter = converter
    }

    // MARK: - API

    func evaluate(content: String) -> [LineOutcome] {
        let lines = content.components(separatedBy: .newlines)
        var variables: [String: Double] = [:]
        var variableUnits: [String: String] = [:]
        var percentVariables = Set<String>()
        var outcomes: [LineOutcome] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("//") || (index == 0 && Self.isMathHeader(trimmed)) {
                outcomes.append(LineOutcome(index: index, original: line, transformed: line))
                continue
            }

            if let assignment = Self.parseVariableAssignment(from: line) {
                if let result = evaluateExpression(
                    assignment.expression,
                    variables: variables,
                    variableUnits: variableUnits,
                    percentVariables: percentVariables
                ), let numeric = result.numericValue {
                    variables[assignment.name] = numeric
                    let key = assignment.name.lowercased()
                    let isRatioPercent = shouldTreatAsUnitlessRatio(expression: assignment.expression, variableUnits: variableUnits)
                    if assignment.expression.contains("%") || isRatioPercent {
                        percentVariables.insert(key)
                    } else {
                        percentVariables.remove(key)
                    }
                    if let unitHint = result.unitHint {
                        variableUnits[assignment.name] = unitHint
                    } else {
                        variableUnits.removeValue(forKey: assignment.name)
                    }

                    // « nom: expr = » affiche aussi le résultat.
                    if assignment.showsResult {
                        let prefix = String(line[..<line.firstIndex(of: "=")!]).trimmingCharacters(in: .whitespaces)
                        outcomes.append(LineOutcome(index: index, original: line, transformed: "\(prefix) = \(result.display)"))
                        continue
                    }
                }
                outcomes.append(LineOutcome(index: index, original: line, transformed: line))
                continue
            }

            if let equalIndex = line.firstIndex(of: "=") {
                let lhs = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                guard !lhs.isEmpty else {
                    outcomes.append(LineOutcome(index: index, original: line, transformed: line))
                    continue
                }

                if let result = evaluateExpression(
                    lhs,
                    variables: variables,
                    variableUnits: variableUnits,
                    percentVariables: percentVariables,
                    forcePercentOutput: percentVariables.contains(lhs.lowercased())
                ) {
                    outcomes.append(LineOutcome(index: index, original: line, transformed: "\(lhs) = \(result.display)"))
                } else {
                    // Expression devenue inévaluable : on vide la partie droite.
                    outcomes.append(LineOutcome(index: index, original: line, transformed: "\(lhs) ="))
                }
                continue
            }

            outcomes.append(LineOutcome(index: index, original: line, transformed: line))
        }

        return outcomes
    }

    func transformed(content: String) -> String {
        evaluate(content: content).map(\.transformed).joined(separator: "\n")
    }

    /// Noms de variables définis dans la note (pour la coloration).
    func variableNames(in content: String) -> Set<String> {
        var names = Set<String>()
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            if index == 0, Self.isMathHeader(line.trimmingCharacters(in: .whitespaces)) { continue }
            if let assignment = Self.parseVariableAssignment(from: line) {
                names.insert(assignment.name)
            }
        }
        return names
    }

    static func isMathHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased == "math" || lowercased.hasPrefix("math:")
    }

    static func isModeKeyword(_ name: String) -> Bool {
        Note.knownKeywords.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    struct Assignment {
        let name: String
        let expression: String
        /// Vrai pour « nom: expr = » (le résultat est affiché après le `=`).
        let showsResult: Bool
    }

    static func parseVariableAssignment(from line: String) -> Assignment? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }

        let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isModeKeyword(name) else { return nil }
        // Un nom de variable est un mot (lettres, chiffres, espaces, _), pas une expression.
        guard name.range(of: #"^[\p{L}_][\p{L}\p{N}_ ]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        var expression = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        var showsResult = false
        if let equalIndex = expression.firstIndex(of: "=") {
            expression = String(expression[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            showsResult = true
        }
        guard !expression.isEmpty else { return nil }

        return Assignment(name: name, expression: expression, showsResult: showsResult)
    }

    // MARK: - Évaluation d'une expression

    struct Result {
        let display: String
        let numericValue: Double?
        let unitHint: String?
        var isError = false
    }

    func evaluateExpression(
        _ expression: String,
        variables: [String: Double] = [:],
        variableUnits: [String: String] = [:],
        percentVariables: Set<String> = [],
        forcePercentOutput: Bool = false
    ) -> Result? {
        let expanded = expandRelativePercentVariables(in: expression, percentVariables: percentVariables)
        let substituted = substituteVariables(in: expanded, variables: variables)

        if let converted = converter.convert(substituted) {
            return Result(
                display: converted,
                numericValue: extractLeadingNumber(from: converted),
                unitHint: extractTrailingUnitHint(from: converted)
            )
        }

        // Conversion de devise dont le taux n'est pas encore chargé : on
        // affiche une attente plutôt qu'un résultat faux.
        if looksLikeCurrencyConversion(substituted) {
            return Result(display: "…", numericValue: nil, unitHint: nil)
        }

        let explicitUnitHintsOrdered = detectExplicitUnitHints(in: expression)
        let explicitUnitHints = Set(explicitUnitHintsOrdered)
        let inferredVariableUnitHints = inferVariableUnitHints(in: expression, variableUnits: variableUnits)
        let combinedHints = explicitUnitHints.union(inferredVariableUnitHints)

        // L'unité préférée est celle qui apparaît en premier dans l'expression.
        let preferredUnit = explicitUnitHintsOrdered.first ?? inferredVariableUnitHints.first
        var unitHint = resolveCompatibleUnitHint(hints: combinedHints, preferred: preferredUnit)

        if shouldTreatAsUnitlessRatio(expression: expression, variableUnits: variableUnits) {
            unitHint = nil
        }

        if combinedHints.count > 1, unitHint == nil {
            return Result(display: "⚠︎ unités incompatibles", numericValue: nil, unitHint: nil, isError: true)
        }

        let normalizedForMath = normalizeUnitLiterals(in: substituted, targetUnit: unitHint)
        let sanitized = sanitize(normalizedForMath)
        guard let value = evaluator.evaluate(sanitized) else {
            return nil
        }

        let display = forcePercentOutput ? "\(Self.format(value * 100))%" : formatWithUnit(value, unitHint: unitHint)
        return Result(display: display, numericValue: value, unitHint: unitHint)
    }

    // MARK: - Variables

    private func substituteVariables(in expression: String, variables: [String: Double]) -> String {
        var resolved = expression
        let sortedNames = variables.keys.sorted { $0.count > $1.count }

        for name in sortedNames {
            guard let value = variables[name] else { continue }
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern: String
            if name.contains(where: { $0.isWhitespace }) {
                pattern = "(?<![\\p{L}\\p{N}_])\(escapedName)(?![\\p{L}\\p{N}_])"
            } else {
                // Évite de remplacer un nom court inclus dans un nom composé.
                pattern = "(?<![\\p{L}\\p{N}_])\(escapedName)(?![\\p{L}\\p{N}_]|\\s+[\\p{L}_])"
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            resolved = regex.stringByReplacingMatches(
                in: resolved, options: [], range: NSRange(resolved.startIndex..., in: resolved),
                withTemplate: "\(value)"
            )
        }
        return resolved
    }

    private func expandRelativePercentVariables(in expression: String, percentVariables: Set<String>) -> String {
        guard !percentVariables.isEmpty else { return expression }
        let parts = splitTopLevelAddSub(expression)
        guard !parts.operators.isEmpty else { return expression }

        var result = parts.terms[0]
        for (index, op) in parts.operators.enumerated() {
            let rhs = parts.terms[index + 1]
            if isPercentVariableTerm(rhs, percentVariables: percentVariables) {
                result = "(\(result) \(op) (\(result) * \(rhs)))"
            } else {
                result = "(\(result) \(op) \(rhs))"
            }
        }
        return result
    }

    private func splitTopLevelAddSub(_ expression: String) -> (terms: [String], operators: [String]) {
        var terms: [String] = []
        var operators: [String] = []
        var depth = 0
        var current = ""
        var previousNonSpace: Character?

        for char in expression {
            if char == "(" { depth += 1; current.append(char); previousNonSpace = char; continue }
            if char == ")" { depth = max(0, depth - 1); current.append(char); previousNonSpace = char; continue }

            if depth == 0, char == "+" || char == "-" {
                let isUnary = previousNonSpace == nil || "(+-*/^".contains(previousNonSpace!)
                if !isUnary {
                    terms.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    operators.append(String(char))
                    current = ""
                    previousNonSpace = nil
                    continue
                }
            }
            current.append(char)
            if !char.isWhitespace { previousNonSpace = char }
        }
        terms.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return (terms, operators)
    }

    private func isPercentVariableTerm(_ term: String, percentVariables: Set<String>) -> Bool {
        var candidate = term.trimmingCharacters(in: .whitespacesAndNewlines)
        while candidate.hasPrefix("("), candidate.hasSuffix(")"), candidate.count >= 2 {
            candidate.removeFirst(); candidate.removeLast()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard candidate.range(of: #"^[\p{L}_][\p{L}\p{N}_]*$"#, options: .regularExpression) != nil else { return false }
        return percentVariables.contains(candidate.lowercased())
    }

    private func sanitize(_ expression: String) -> String {
        expression
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeCurrencyConversion(_ expression: String) -> Bool {
        expression.range(
            of: #"(?i)^\s*[-+]?\d+(?:[.,]\d+)?\s*[A-Za-z]{3}\s+(to|in|en)\s+[A-Za-z]{3}\s*=?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private func extractLeadingNumber(from text: String) -> Double? {
        guard let range = text.range(of: #"[-+]?\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Unités

    private struct UnitDescriptor {
        let canonical: String
        let family: String
        let dimension: Dimension?
    }

    private func detectExplicitUnitHints(in expression: String) -> [String] {
        var hints: [String] = []
        let pattern = "[-+]?\\d+(?:[.,]\\d+)?\\s*(€|\\$|£|¥|￥|[A-Za-z°²]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return hints }
        for match in regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)) {
            guard let range = Range(match.range(at: 1), in: expression) else { continue }
            if let canonical = Self.canonicalUnitToken(String(expression[range])), !hints.contains(canonical) {
                hints.append(canonical)
            }
        }
        return hints
    }

    private func variableRegex(_ name: String) -> NSRegularExpression? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])", options: [.caseInsensitive])
    }

    private func inferVariableUnitHints(in expression: String, variableUnits: [String: String]) -> Set<String> {
        var hints = Set<String>()
        for (name, unit) in variableUnits {
            guard let regex = variableRegex(name) else { continue }
            if regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)) != nil,
               let canonical = Self.canonicalUnitToken(unit) {
                hints.insert(canonical)
            }
        }
        return hints
    }

    private func shouldTreatAsUnitlessRatio(expression: String, variableUnits: [String: String]) -> Bool {
        guard expression.contains("/") else { return false }
        var matched: [String] = []
        for (name, unit) in variableUnits {
            guard let regex = variableRegex(name),
                  let canonical = Self.canonicalUnitToken(unit) else { continue }
            let count = regex.numberOfMatches(in: expression, range: NSRange(expression.startIndex..., in: expression))
            matched.append(contentsOf: Array(repeating: canonical, count: count))
        }
        guard matched.count >= 2 else { return false }
        return Set(matched.compactMap { unitDescriptor(for: $0)?.family }).count == 1
    }

    private func extractTrailingUnitHint(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "[-+]?\\d+(?:[.,]\\d+)?\\s*([^0-9\\s]+|[A-Za-z°²]+)$"),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let unitRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        return Self.canonicalUnitToken(String(trimmed[unitRange]))
    }

    private func resolveCompatibleUnitHint(hints: Set<String>, preferred: String?) -> String? {
        guard !hints.isEmpty else { return nil }
        if hints.count == 1 { return hints.first }

        let descriptors = hints.compactMap { unitDescriptor(for: $0) }
        guard descriptors.count == hints.count,
              Set(descriptors.map(\.family)).count == 1 else { return nil }

        if descriptors.first?.family == "currency",
           Set(descriptors.map { Self.currencyCode(for: $0.canonical) }).count != 1 {
            return nil
        }

        if let preferred, let canonical = Self.canonicalUnitToken(preferred), hints.contains(canonical) {
            return canonical
        }
        return hints.first
    }

    private func normalizeUnitLiterals(in expression: String, targetUnit: String?) -> String {
        guard let targetUnit, let target = unitDescriptor(for: targetUnit),
              let regex = try? NSRegularExpression(pattern: "([-+]?\\d+(?:[.,]\\d+)?)\\s*(€|\\$|£|¥|￥|[A-Za-z°²]+)") else {
            return expression
        }

        var result = expression
        for match in regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)).reversed() {
            guard let valueRange = Range(match.range(at: 1), in: expression),
                  let unitRange = Range(match.range(at: 2), in: expression),
                  let fullRange = Range(match.range, in: result),
                  let value = Double(expression[valueRange].replacingOccurrences(of: ",", with: ".")),
                  let source = unitDescriptor(for: String(expression[unitRange])),
                  source.family == target.family else {
                continue
            }

            if target.family == "currency" {
                guard Self.currencyCode(for: source.canonical) == Self.currencyCode(for: target.canonical) else { continue }
                result.replaceSubrange(fullRange, with: Self.format(value))
                continue
            }

            guard let sourceDimension = source.dimension, let targetDimension = target.dimension else { continue }
            let base = sourceDimension.converter.baseUnitValue(fromValue: value)
            result.replaceSubrange(fullRange, with: Self.format(targetDimension.converter.value(fromBaseUnitValue: base)))
        }
        return result
    }

    private func unitDescriptor(for token: String) -> UnitDescriptor? {
        guard let canonical = Self.canonicalUnitToken(token) else { return nil }
        let family = Self.unitFamily(for: canonical)
        let dimension: Dimension?
        switch canonical {
        case "$", "€", "£", "¥", "usd", "eur", "gbp", "jpy", "chf", "cad": dimension = nil
        case "mm": dimension = UnitLength.millimeters
        case "cm": dimension = UnitLength.centimeters
        case "m": dimension = UnitLength.meters
        case "km": dimension = UnitLength.kilometers
        case "in": dimension = UnitLength.inches
        case "ft": dimension = UnitLength.feet
        case "yd": dimension = UnitLength.yards
        case "mi": dimension = UnitLength.miles
        case "mm2": dimension = UnitArea.squareMillimeters
        case "cm2": dimension = UnitArea.squareCentimeters
        case "m2": dimension = UnitArea.squareMeters
        case "km2": dimension = UnitArea.squareKilometers
        case "ft2": dimension = UnitArea.squareFeet
        case "in2": dimension = UnitArea.squareInches
        case "yd2": dimension = UnitArea.squareYards
        case "mi2": dimension = UnitArea.squareMiles
        case "ha": dimension = UnitArea.hectares
        case "acre": dimension = UnitArea.acres
        case "are": dimension = UnitArea.ares
        case "ml": dimension = UnitVolume.milliliters
        case "l": dimension = UnitVolume.liters
        case "gal": dimension = UnitVolume.gallons
        case "qt": dimension = UnitVolume.quarts
        case "pt": dimension = UnitVolume.pints
        case "cup": dimension = UnitVolume.cups
        case "mg": dimension = UnitMass.milligrams
        case "g": dimension = UnitMass.grams
        case "kg": dimension = UnitMass.kilograms
        case "lb": dimension = UnitMass.pounds
        case "oz": dimension = UnitMass.ounces
        case "°c": dimension = UnitTemperature.celsius
        case "°f": dimension = UnitTemperature.fahrenheit
        case "k": dimension = UnitTemperature.kelvin
        case "s": dimension = UnitDuration.seconds
        case "min": dimension = UnitDuration.minutes
        case "h": dimension = UnitDuration.hours
        default: return nil
        }
        return UnitDescriptor(canonical: canonical, family: family, dimension: dimension)
    }

    static func unitFamily(for hint: String) -> String {
        switch hint {
        case "$", "€", "£", "¥", "usd", "eur", "gbp", "jpy", "chf", "cad": return "currency"
        case "mm", "cm", "m", "km", "in", "ft", "yd", "mi": return "length"
        case "mm2", "cm2", "m2", "km2", "ft2", "in2", "yd2", "mi2", "ha", "acre", "are": return "area"
        case "ml", "l", "gal", "qt", "pt", "cup": return "volume"
        case "mg", "g", "kg", "lb", "oz": return "mass"
        case "°c", "°f", "k": return "temperature"
        case "s", "min", "h": return "duration"
        default: return "unknown"
        }
    }

    static func currencyCode(for unit: String) -> String {
        switch unit.lowercased() {
        case "€", "eur": return "eur"
        case "$", "usd": return "usd"
        case "£", "gbp": return "gbp"
        case "¥", "jpy": return "jpy"
        default: return unit.lowercased()
        }
    }

    static func canonicalUnitToken(_ rawToken: String) -> String? {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return nil }
        switch token {
        case "￥": return "¥"
        case "€", "$", "£", "¥": return token
        default: break
        }

        switch token.lowercased() {
        case "usd", "eur", "gbp", "jpy", "chf", "cad": return token.lowercased()
        case "mm", "millimeter", "millimetre", "millimeters", "millimetres": return "mm"
        case "cm", "centimeter", "centimetre", "centimeters", "centimetres": return "cm"
        case "m", "meter", "metre", "meters", "metres": return "m"
        case "km", "kilometer", "kilometre", "kilometers", "kilometres": return "km"
        case "in", "inch", "inches": return "in"
        case "ft", "foot", "feet": return "ft"
        case "yd", "yard", "yards": return "yd"
        case "mi", "mile", "miles": return "mi"
        case "mm²", "sqmm", "squaremillimeter", "squaremillimeters", "squaremm": return "mm2"
        case "cm²", "sqcm", "squarecentimeter", "squarecentimeters", "squarecm": return "cm2"
        case "m²", "sqm", "sqmeter", "sqmeters", "squaremeter", "squaremeters", "squarem": return "m2"
        case "km²", "sqkm", "squarekilometer", "squarekilometers", "squarekm": return "km2"
        case "ft²", "sqft", "squarefoot", "squarefeet", "squareft": return "ft2"
        case "in²", "sqin", "squareinch", "squareinches", "squarein": return "in2"
        case "yd²", "sqyd", "squareyard", "squareyards", "squareyd": return "yd2"
        case "mi²", "sqmi", "squaremile", "squaremiles", "squaremi": return "mi2"
        case "ha", "hectare", "hectares": return "ha"
        case "acre", "acres": return "acre"
        case "are", "ares": return "are"
        case "ml", "milliliter", "millilitre", "milliliters", "millilitres": return "ml"
        case "l", "liter", "litre", "liters", "litres": return "l"
        case "gal", "gallon", "gallons": return "gal"
        case "qt", "quart", "quarts": return "qt"
        case "pt", "pint", "pints": return "pt"
        case "cup", "cups": return "cup"
        case "mg", "milligram", "milligrams", "mgs": return "mg"
        case "g", "gram", "grams", "gs": return "g"
        case "kg", "kilogram", "kilograms", "kgs": return "kg"
        case "lb", "lbs", "pound", "pounds": return "lb"
        case "oz", "ozs", "ounce", "ounces": return "oz"
        case "c", "°c", "celsius", "centigrade": return "°c"
        case "f", "°f", "fahrenheit": return "°f"
        case "k", "kelvin", "kelvins": return "k"
        case "s", "sec", "secs", "second", "seconds": return "s"
        case "min", "mins", "mn", "minute", "minutes": return "min"
        case "h", "hr", "hrs", "hour", "hours": return "h"
        default: return nil
        }
    }

    // MARK: - Format

    private func formatWithUnit(_ value: Double, unitHint: String?) -> String {
        let number = Self.format(value)
        guard let unitHint, !unitHint.isEmpty else { return number }
        if ["€", "$", "£", "¥"].contains(unitHint) { return "\(number)\(unitHint)" }
        return "\(number) \(unitHint)"
    }

    static func format(_ value: Double) -> String {
        if !value.isFinite { return String(value) }
        if value == floor(value), Swift.abs(value) < 1e15 { return String(Int64(value)) }
        var formatted = String(format: "%.4f", value)
        while formatted.last == "0" { formatted.removeLast() }
        if formatted.last == "." { formatted.removeLast() }
        return formatted
    }
}
