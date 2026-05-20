import SwiftUI

struct ListNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14

    private var lines: [String] {
        note.content.components(separatedBy: .newlines)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    listRow(for: line, index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func listRow(for line: String, index: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            Text(line)
                .font(.system(size: fontSize + 2, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if trimmed.hasPrefix("/x") || trimmed.hasPrefix("/X") {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: fontSize))
                Text(contentWithoutMarker(line))
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleItem(at: index, checked: true)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: fontSize))
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleItem(at: index, checked: false)
            }
        }
    }

    private func contentWithoutMarker(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/x") || trimmed.hasPrefix("/X") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private func toggleItem(at index: Int, checked: Bool) {
        var lines = note.content.components(separatedBy: .newlines)
        guard index >= 0 && index < lines.count else { return }

        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if checked {
            let content = contentWithoutMarker(lines[index])
            lines[index] = content
        } else {
            if trimmed.hasPrefix("/x") || trimmed.hasPrefix("/X") {
                let content = contentWithoutMarker(lines[index])
                lines[index] = content
            } else {
                lines[index] = "/x \(trimmed)"
            }
        }
        note.content = lines.joined(separator: "\n")
    }
}