import SwiftUI

struct MathNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14
    @State private var evaluator = MathEvaluator()
    @State private var converter = Converter()
    @FocusState private var isEditorFocused: Bool
    @State private var isApplyingTransformation = false
    @State private var pendingSource: String = ""

    var body: some View {
        TextEditor(text: $note.content)
            .font(.system(size: fontSize, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onAppear {
                isEditorFocused = true
                queueMathBehavior(for: note.content)
            }
            .onChange(of: note.content) {
                queueMathBehavior(for: note.content)
            }
    }

    private func queueMathBehavior(for source: String) {
        pendingSource = source

        DispatchQueue.main.async {
            let sourceToProcess = pendingSource
            applyMathBehavior(to: sourceToProcess)
        }
    }

    private func applyMathBehavior(to source: String) {
        guard !isApplyingTransformation else { return }

        let transformed = transformMathContent(source)
        if transformed != source {
            isApplyingTransformation = true
            note.content = transformed
            isApplyingTransformation = false
        }

        note.detectKeyword()
    }

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
