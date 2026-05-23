import SwiftUI

struct MathNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore
    private let evaluator = MathEvaluator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $note.content)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)

            Divider()
                .padding(.horizontal, 12)

            // Live evaluation results
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(evaluatedLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 150)
        }
    }

    private var evaluatedLines: [String] {
        note.content
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix("=") }
            .compactMap { line -> String? in
                let expr = String(line.dropLast())
                    .trimmingCharacters(in: .whitespaces)
                guard let result = evaluator.evaluate(expr) else { return nil }
                return "  = \(formatNumber(result))"
            }
    }

    private func formatNumber(_ value: Double) -> String {
        value == floor(value) ? String(Int64(value)) : String(format: "%.4g", value)
    }
}
