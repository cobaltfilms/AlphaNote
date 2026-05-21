import SwiftUI
import AppKit

struct MathNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14

    var body: some View {
        MathColoringEditor(
            text: $note.content,
            fontSize: fontSize,
            onTextChange: { updated in
                note.content = updated
                note.detectKeyword()
            }
        )
    }
}

private struct MathColoringEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)

        if context.coordinator.isProgrammaticChange {
            return
        }

        if textView.string != text {
            let oldSelection = textView.selectedRange()
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)

            let clampedLocation = min(oldSelection.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            context.coordinator.isProgrammaticChange = false
        } else {
            context.coordinator.applyHighlighting(to: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MathColoringEditor
        var isProgrammaticChange = false

        private let evaluator = MathEvaluator()
        private let converter = Converter()

        init(parent: MathColoringEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isProgrammaticChange else {
                return
            }

            let source = textView.string
            let transformed = transformMathContent(source)

            if transformed != source {
                let oldSelection = textView.selectedRange()
                isProgrammaticChange = true
                textView.string = transformed
                let clampedLocation = min(oldSelection.location, (transformed as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
                isProgrammaticChange = false
            }

            applyHighlighting(to: textView)
            parent.onTextChange(textView.string)
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)

            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            let lines = text.components(separatedBy: .newlines)
            var variableNames = Set<String>()
            for (index, line) in lines.enumerated() {
                if index == 0, isMathHeader(line.trimmingCharacters(in: .whitespaces)) {
                    continue
                }
                if let assignment = parseVariableAssignment(from: line) {
                    variableNames.insert(assignment.name)
                }
            }

            var location = 0
            for (index, line) in lines.enumerated() {
                let nsLine = line as NSString
                let lineRange = NSRange(location: location, length: nsLine.length)
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if index == 0, isMathHeader(trimmed) {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor
                    ], range: lineRange)
                }

                if let colonIndex = line.firstIndex(of: ":") {
                    let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        let distance = line.distance(from: line.startIndex, to: colonIndex)
                        let nameRange = NSRange(location: lineRange.location, length: distance)
                        if nameRange.length > 0 {
                            textStorage.addAttributes([
                                .foregroundColor: NSColor.systemOrange,
                                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold)
                            ], range: nameRange)
                        }
                    }
                }

                if let equalIndex = line.firstIndex(of: "=") {
                    let prefixLength = line.distance(from: line.startIndex, to: equalIndex)
                    let eqRange = NSRange(location: lineRange.location + prefixLength, length: 1)
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ], range: eqRange)

                    let resultStart = line.index(after: equalIndex)
                    let result = String(line[resultStart...]).trimmingCharacters(in: .whitespaces)
                    if !result.isEmpty {
                        let resultOffset = line.distance(from: line.startIndex, to: resultStart)
                        let resultRange = NSRange(
                            location: lineRange.location + resultOffset,
                            length: max(0, lineRange.length - resultOffset)
                        )
                        if resultRange.length > 0 {
                            textStorage.addAttributes([
                                .foregroundColor: NSColor.systemGreen
                            ], range: resultRange)
                        }
                    }
                }

                highlightRegex(Self.numberRegex, color: NSColor.systemBlue, in: lineRange, textStorage: textStorage)
                highlightRegex(Self.unitRegex, color: NSColor.systemTeal, in: lineRange, textStorage: textStorage)

                for name in variableNames {
                    let escaped = NSRegularExpression.escapedPattern(for: name)
                    let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    highlightRegex(regex, color: NSColor.systemOrange, in: lineRange, textStorage: textStorage)
                }

                location += nsLine.length
                if index < lines.count - 1 {
                    location += 1
                }
            }

            textStorage.endEditing()
        }

        private func highlightRegex(
            _ regex: NSRegularExpression,
            color: NSColor,
            in range: NSRange,
            textStorage: NSTextStorage
        ) {
            let matches = regex.matches(in: textStorage.string, options: [], range: range)
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: color
                ], range: match.range)
            }
        }

        private static let numberRegex = try! NSRegularExpression(pattern: "(?<![\\p{L}_])[-+]?\\d+(?:[.,]\\d+)?")
        private static let unitRegex = try! NSRegularExpression(pattern: "(?i)\\b(usd|eur|gbp|jpy|kg|g|mg|lb|oz|km|m|cm|mm|mi|yd|ft|in|sqm|sqft|ha|acre|l|ml|gal|qt|pt|cup|°c|°f|k)\\b")

        private func transformMathContent(_ content: String) -> String {
            let lines = content.components(separatedBy: .newlines)
            var variables: [String: Double] = [:]
            var variableUnits: [String: String] = [:]
            var transformedLines: [String] = []

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty || trimmed.hasPrefix("//") {
                    transformedLines.append(line)
                    continue
                }

                if index == 0, isMathHeader(trimmed) {
                    transformedLines.append(line)
                    continue
                }

                if let assignment = parseVariableAssignment(from: line),
                   let result = evaluateExpression(
                    assignment.expression,
                    variables: variables,
                    variableUnits: variableUnits
                   ),
                   let numeric = result.numericValue {
                    variables[assignment.name] = numeric
                    if let unitHint = result.unitHint {
                        variableUnits[assignment.name] = unitHint
                    }
                    transformedLines.append(line)
                    continue
                }

                if let equalIndex = line.firstIndex(of: "=") {
                    let lhs = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                    guard !lhs.isEmpty else {
                        transformedLines.append(line)
                        continue
                    }

                    if let result = evaluateExpression(
                        lhs,
                        variables: variables,
                        variableUnits: variableUnits
                    ) {
                        transformedLines.append("\(lhs) = \(result.display)")
                    } else {
                        // Clear stale right-hand values when expression can no longer be evaluated.
                        transformedLines.append("\(lhs) =")
                    }
                    continue
                }

                transformedLines.append(line)
            }

            return transformedLines.joined(separator: "\n")
        }

        private func isMathHeader(_ line: String) -> Bool {
            let lowercased = line.lowercased()
            return lowercased == "math" || lowercased.hasPrefix("math:")
        }

        private func parseVariableAssignment(from line: String) -> (name: String, expression: String)? {
            guard let colonIndex = line.firstIndex(of: ":") else {
                return nil
            }

            let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return nil
            }

            var expression = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if let equalIndex = expression.firstIndex(of: "=") {
                expression = String(expression[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            }

            guard !expression.isEmpty else {
                return nil
            }

            return (name, expression)
        }

        private struct MathEvaluationResult {
            let display: String
            let numericValue: Double?
            let unitHint: String?
            let isError: Bool

            init(display: String, numericValue: Double?, unitHint: String?, isError: Bool = false) {
                self.display = display
                self.numericValue = numericValue
                self.unitHint = unitHint
                self.isError = isError
            }
        }

        private func evaluateExpression(
            _ expression: String,
            variables: [String: Double],
            variableUnits: [String: String]
        ) -> MathEvaluationResult? {
            let substituted = substituteVariables(in: expression, variables: variables)

            if let converted = converter.convert(substituted) {
                let numeric = extractLeadingNumber(from: converted)
                return MathEvaluationResult(
                    display: converted,
                    numericValue: numeric,
                    unitHint: extractTrailingUnitHint(from: converted)
                )
            }

            let explicitUnitHints = detectExplicitUnitHints(in: expression)
            let inferredVariableUnitHints = inferVariableUnitHints(in: expression, variableUnits: variableUnits)
            let combinedHints = explicitUnitHints.union(inferredVariableUnitHints)

            let preferredUnit = inferredVariableUnitHints.first ?? explicitUnitHints.first
            let unitHint = resolveCompatibleUnitHint(hints: combinedHints, preferred: preferredUnit)

            if combinedHints.count > 1, unitHint == nil {
                return MathEvaluationResult(
                    display: "⚠︎ mixed units",
                    numericValue: nil,
                    unitHint: nil,
                    isError: true
                )
            }

            let normalizedForMath = normalizeUnitLiterals(in: substituted, targetUnit: unitHint)
            let sanitized = sanitizeMathExpression(normalizedForMath)
            guard let value = evaluator.evaluate(sanitized) else {
                return nil
            }

            return MathEvaluationResult(
                display: formatWithUnit(value, unitHint: unitHint),
                numericValue: value,
                unitHint: unitHint
            )
        }

        private func substituteVariables(in expression: String, variables: [String: Double]) -> String {
            var resolved = expression
            let sortedNames = variables.keys.sorted { $0.count > $1.count }

            for name in sortedNames {
                guard let value = variables[name] else { continue }
                let escapedName = NSRegularExpression.escapedPattern(for: name)
                let pattern = "(?<![\\p{L}\\p{N}_])\(escapedName)(?![\\p{L}\\p{N}_])"

                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                resolved = regex.stringByReplacingMatches(
                    in: resolved,
                    options: [],
                    range: NSRange(resolved.startIndex..., in: resolved),
                    withTemplate: "\(value)"
                )
            }

            return resolved
        }

        private func sanitizeMathExpression(_ expression: String) -> String {
            var text = expression
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "£", with: "")
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "￥", with: "")

            if let regex = try? NSRegularExpression(pattern: "[^0-9+\\-*/^().,% xX÷of]") {
                text = regex.stringByReplacingMatches(
                    in: text,
                    options: [],
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }

            return text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func extractLeadingNumber(from text: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: "[-+]?\\d+(?:[.,]\\d+)?"),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else {
                return nil
            }

            let valueText = text[range].replacingOccurrences(of: ",", with: ".")
            return Double(valueText)
        }

        private struct UnitDescriptor {
            let canonical: String
            let family: String
            let dimension: Dimension?
        }

        private func detectExplicitUnitHints(in expression: String) -> Set<String> {
            var hints = Set<String>()
            let pattern = "[-+]?\\d+(?:[.,]\\d+)?\\s*(€|\\$|£|¥|￥|[A-Za-z°²]+)"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression))
                for match in matches {
                    guard let range = Range(match.range(at: 1), in: expression) else { continue }
                    let token = String(expression[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let canonical = canonicalUnitToken(token) {
                        hints.insert(canonical)
                    }
                }
            }
            return hints
        }

        private func inferVariableUnitHints(in expression: String, variableUnits: [String: String]) -> Set<String> {
            let names = variableNamesInExpression(expression)
            let hints = names.compactMap { variableUnits[$0] }.compactMap { canonicalUnitToken($0) }
            return Set(hints)
        }

        private func variableNamesInExpression(_ expression: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*") else {
                return []
            }
            let matches = regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression))
            return matches.compactMap { match in
                guard let range = Range(match.range, in: expression) else { return nil }
                return String(expression[range])
            }
        }

        private func extractTrailingUnitHint(from text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let regex = try? NSRegularExpression(pattern: "[-+]?\\d+(?:[.,]\\d+)?\\s*([^0-9\\s]+|[A-Za-z°²]+)$"),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let unitRange = Range(match.range(at: 1), in: trimmed),
                  let canonical = canonicalUnitToken(String(trimmed[unitRange])) else {
                return nil
            }
            return canonical
        }

        private func resolveCompatibleUnitHint(hints: Set<String>, preferred: String?) -> String? {
            guard !hints.isEmpty else { return nil }
            if hints.count == 1 { return hints.first }

            let descriptors = hints.compactMap { unitDescriptor(for: $0) }
            guard descriptors.count == hints.count else { return nil }

            let families = Set(descriptors.map { $0.family })
            guard families.count == 1 else { return nil }

            if descriptors.first?.family == "currency" {
                let currencies = Set(descriptors.map { currencyCode(for: $0.canonical) })
                guard currencies.count == 1 else { return nil }
            }

            if let preferred,
               let preferredCanonical = canonicalUnitToken(preferred),
               hints.contains(preferredCanonical) {
                return preferredCanonical
            }

            return hints.first
        }

        private func normalizeUnitLiterals(in expression: String, targetUnit: String?) -> String {
            guard let targetUnit,
                  let target = unitDescriptor(for: targetUnit),
                  let regex = try? NSRegularExpression(pattern: "([-+]?\\d+(?:[.,]\\d+)?)\\s*(€|\\$|£|¥|￥|[A-Za-z°²]+)") else {
                return expression
            }

            var result = expression
            let matches = regex.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)).reversed()

            for match in matches {
                guard let valueRange = Range(match.range(at: 1), in: expression),
                      let unitRange = Range(match.range(at: 2), in: expression),
                      let fullRange = Range(match.range, in: result) else {
                    continue
                }

                let valueText = String(expression[valueRange]).replacingOccurrences(of: ",", with: ".")
                guard let value = Double(valueText),
                      let source = unitDescriptor(for: String(expression[unitRange])),
                      source.family == target.family else {
                    continue
                }

                if target.family == "currency" {
                    guard currencyCode(for: source.canonical) == currencyCode(for: target.canonical) else {
                        continue
                    }
                    result.replaceSubrange(fullRange, with: format(value))
                    continue
                }

                guard let sourceDimension = source.dimension,
                      let targetDimension = target.dimension else {
                    continue
                }

                let base = sourceDimension.converter.baseUnitValue(fromValue: value)
                let converted = targetDimension.converter.value(fromBaseUnitValue: base)
                result.replaceSubrange(fullRange, with: format(converted))
            }

            return result
        }

        private func unitDescriptor(for token: String) -> UnitDescriptor? {
            guard let canonical = canonicalUnitToken(token) else { return nil }
            let family = unitFamily(for: canonical)

            switch canonical {
            case "$", "€", "£", "¥", "usd", "eur", "gbp", "jpy":
                return UnitDescriptor(canonical: canonical, family: family, dimension: nil)
            case "mm": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.millimeters)
            case "cm": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.centimeters)
            case "m": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.meters)
            case "km": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.kilometers)
            case "in": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.inches)
            case "ft": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.feet)
            case "yd": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.yards)
            case "mi": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitLength.miles)
            case "mm2": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareMillimeters)
            case "cm2": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareCentimeters)
            case "m2", "sqm": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareMeters)
            case "km2", "sqkm": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareKilometers)
            case "ft2", "sqft": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareFeet)
            case "in2", "sqin": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareInches)
            case "yd2", "sqyd": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareYards)
            case "mi2", "sqmi": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.squareMiles)
            case "ha": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.hectares)
            case "acre": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.acres)
            case "are": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitArea.ares)
            case "ml": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.milliliters)
            case "l": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.liters)
            case "gal": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.gallons)
            case "qt": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.quarts)
            case "pt": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.pints)
            case "cup": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitVolume.cups)
            case "mg": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitMass.milligrams)
            case "g": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitMass.grams)
            case "kg": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitMass.kilograms)
            case "lb": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitMass.pounds)
            case "oz": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitMass.ounces)
            case "c", "°c": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitTemperature.celsius)
            case "f", "°f": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitTemperature.fahrenheit)
            case "k": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitTemperature.kelvin)
            case "s": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitDuration.seconds)
            case "min": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitDuration.minutes)
            case "h": return UnitDescriptor(canonical: canonical, family: family, dimension: UnitDuration.hours)
            default:
                return nil
            }
        }

        private func unitFamily(for hint: String) -> String {
            switch hint {
            case "$", "€", "£", "¥", "usd", "eur", "gbp", "jpy": return "currency"
            case "mm", "cm", "m", "km", "in", "ft", "yd", "mi": return "length"
            case "mm2", "cm2", "m2", "sqm", "km2", "sqkm", "ft2", "sqft", "in2", "sqin", "yd2", "sqyd", "mi2", "sqmi", "ha", "acre", "are": return "area"
            case "ml", "l", "gal", "qt", "pt", "cup": return "volume"
            case "mg", "g", "kg", "lb", "oz": return "mass"
            case "c", "°c", "f", "°f", "k": return "temperature"
            case "s", "min", "h": return "duration"
            default: return "unknown"
            }
        }

        private func currencyCode(for unit: String) -> String {
            switch unit.lowercased() {
            case "€", "eur": return "eur"
            case "$", "usd": return "usd"
            case "£", "gbp": return "gbp"
            case "¥", "jpy": return "jpy"
            default: return unit.lowercased()
            }
        }

        private func canonicalUnitToken(_ rawToken: String) -> String? {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return nil }

            switch token {
            case "￥": return "¥"
            case "€", "$", "£", "¥": return token
            default:
                break
            }

            let lower = token.lowercased()
            switch lower {
            case "usd", "eur", "gbp", "jpy": return lower
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

        private func formatWithUnit(_ value: Double, unitHint: String?) -> String {
            let number = format(value)
            guard let unitHint, !unitHint.isEmpty else {
                return number
            }

            if ["€", "$", "£", "¥"].contains(unitHint) {
                return "\(number)\(unitHint)"
            }

            return "\(number) \(unitHint)"
        }

        private func format(_ value: Double) -> String {
            if !value.isFinite { return String(value) }

            if value == floor(value) {
                return String(Int64(value))
            }

            var formatted = String(format: "%.6f", value)
            while formatted.last == "0" {
                formatted.removeLast()
            }
            if formatted.last == "." {
                formatted.removeLast()
            }
            return formatted
        }
    }
}
