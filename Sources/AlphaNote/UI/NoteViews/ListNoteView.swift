import SwiftUI

struct ListNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("listCheckTrigger") private var listCheckTrigger: String = "/x"
    @State private var isEditing = false
    @FocusState private var isEditorFocused: Bool

    private struct Row: Identifiable {
        let id: Int
        let rawIndex: Int
        let line: String
    }

    private var lines: [String] {
        note.content.components(separatedBy: .newlines)
    }

    private var listTitle: String? {
        guard let first = lines.first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("list:") else { return nil }
        let title = String(trimmed.dropFirst("list:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private var rows: [Row] {
        let startIndex = (lines.first.map(ListModeFormatter.isListHeader) ?? false) ? 1 : 0
        return lines.enumerated().compactMap { index, line in
            guard index >= startIndex else { return nil }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Row(id: index, rawIndex: index, line: line)
        }
    }

    private var checkTrigger: String {
        let trimmed = listCheckTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/x" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Édition de la liste" : "Liste")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isEditing ? "Terminer" : "Modifier") {
                    if isEditing {
                        let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: true)
                        if normalized != note.content {
                            note.content = normalized
                        }
                        isEditing = false
                    } else {
                        isEditing = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if isEditing {
                TextEditor(text: $note.content)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Palette.textColor)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .onAppear {
                        isEditorFocused = true
                    }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if let listTitle {
                            Text(listTitle)
                                .font(.system(size: fontSize + 4, weight: .semibold))
                                .padding(.bottom, 4)
                        }

                        ForEach(rows) { row in
                            listRow(for: row)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear {
            normalizeContentIfNeeded()
        }
    }

    @ViewBuilder
    private func listRow(for row: Row) -> some View {
        let trimmed = row.line.trimmingCharacters(in: .whitespacesAndNewlines)

        if ListModeFormatter.isHeading(trimmed) {
            headingRow(trimmed)
        } else if ListModeFormatter.isComment(trimmed) {
            commentRow(trimmed)
        } else {
            checklistRow(line: row.line, rawIndex: row.rawIndex)
        }
    }

    private func headingRow(_ line: String) -> some View {
        Text(line)
            .font(.system(size: fontSize + 2, weight: .bold))
            .foregroundStyle(Palette.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentRow(_ line: String) -> some View {
        Text(line)
            .font(.system(size: fontSize))
            .foregroundStyle(Palette.secondaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checklistRow(line: String, rawIndex: Int) -> some View {
        let checked = isCheckedLine(line)
        let itemText = contentWithoutCheckTrigger(line)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color(nsColor: Palette.list) : Palette.secondaryColor)
                .font(.system(size: fontSize))
            Text(itemText.isEmpty ? " " : itemText)
                .font(.system(size: fontSize))
                .foregroundStyle(checked ? Palette.secondaryColor : Palette.textColor)
                .strikethrough(checked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleItem(at: rawIndex, checked: checked)
        }
    }

    private func isCheckedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(
            of: checkTrigger,
            options: [.caseInsensitive, .anchored, .backwards]
        ) != nil
    }

    private func contentWithoutCheckTrigger(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(
            of: checkTrigger,
            options: [.caseInsensitive, .anchored, .backwards]
        ) else {
            return trimmed
        }

        let withoutTrigger = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(withoutTrigger)
    }

    private func toggleItem(at rawIndex: Int, checked: Bool) {
        var rawLines = lines
        guard rawIndex >= 0 && rawIndex < rawLines.count else { return }

        let current = rawLines[rawIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        if checked {
            rawLines[rawIndex] = contentWithoutCheckTrigger(current)
        } else {
            let base = contentWithoutCheckTrigger(current)
            rawLines[rawIndex] = base.isEmpty ? checkTrigger : "\(base) \(checkTrigger)"
        }
        note.content = rawLines.joined(separator: "\n")
    }

    private func normalizeContentIfNeeded() {
        let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: false)
        if normalized != note.content {
            note.content = normalized
        }
    }
}
