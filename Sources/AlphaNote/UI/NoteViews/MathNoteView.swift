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
                   let result = evaluateExpression(assignment.expression, variables: variables),
                   let numeric = result.numericValue {
                    variables[assignment.name] = numeric
                    transformedLines.append(line)
                    continue
                }

                if let equalIndex = line.firstIndex(of: "=") {
                    let lhs = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                    guard !lhs.isEmpty else {
                        transformedLines.append(line)
                        continue
                    }

                    if let result = evaluateExpression(lhs, variables: variables) {
                        transformedLines.append("\(lhs) = \(result.display)")
                    } else {
                        transformedLines.append(line)
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
        }

        private func evaluateExpression(_ expression: String, variables: [String: Double]) -> MathEvaluationResult? {
            let substituted = substituteVariables(in: expression, variables: variables)

            if let converted = converter.convert(substituted) {
                let numeric = extractLeadingNumber(from: converted)
                return MathEvaluationResult(display: converted, numericValue: numeric)
            }

            let sanitized = sanitizeMathExpression(substituted)
            guard let value = evaluator.evaluate(sanitized) else {
                return nil
            }

            return MathEvaluationResult(display: format(value), numericValue: value)
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
