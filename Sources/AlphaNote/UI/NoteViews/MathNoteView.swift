import SwiftUI

struct MathNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14
    @State private var evaluator = MathEvaluator()
    @State private var evaluatedLines: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let lines = note.content.components(separatedBy: .newlines)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Spacer()
                            if let result = evaluatedLines[index] {
                                Text("= \(result)")
                                    .font(.system(size: fontSize - 1, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            TextEditor(text: $note.content)
                .font(.system(size: fontSize, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: note.content) {
                    evaluateAllLines()
                    note.detectKeyword()
                }
        }
        .onAppear {
            evaluateAllLines()
        }
    }

    private func evaluateAllLines() {
        evaluatedLines.removeAll(keepingCapacity: true)
        let lines = note.content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasSuffix("=") {
                let expression = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if let result = evaluator.evaluate(expression) {
                    let formatted: String
                    if result == floor(result) && abs(result) < Double(Int64.max) {
                        formatted = String(Int64(result))
                    } else {
                        formatted = String(format: "%.6g", result)
                    }
                    evaluatedLines[index] = formatted
                }
            } else if let result = evaluator.evaluate(trimmed) {
                let formatted: String
                if result == floor(result) && abs(result) < Double(Int64.max) {
                    formatted = String(Int64(result))
                } else {
                    formatted = String(format: "%.6g", result)
                }
                evaluatedLines[index] = formatted
            }
        }
    }
}