import SwiftUI

struct CodeNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14
    @FocusState private var isEditorFocused: Bool

    private var detectedLanguage: String {
        let titleLine = note.effectiveTitle.lowercased()
        if titleLine.contains("swift") { return "swift" }
        if titleLine.contains("python") || titleLine.contains("py") { return "python" }
        if titleLine.contains("javascript") || titleLine.contains("js") { return "javascript" }
        if titleLine.contains("rust") { return "rust" }
        if titleLine.contains("ruby") { return "ruby" }
        if titleLine.contains("go") { return "go" }
        if titleLine.contains("c++") || titleLine.contains("cpp") { return "c++" }
        if titleLine.contains("java") && !titleLine.contains("javascript") { return "java" }
        if titleLine.contains("html") { return "html" }
        if titleLine.contains("css") { return "css" }
        if titleLine.contains("shell") || titleLine.contains("bash") || titleLine.contains("zsh") { return "shell" }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !detectedLanguage.isEmpty {
                HStack {
                    Text(detectedLanguage.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            TextEditor(text: $note.content)
                .font(.system(size: fontSize, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onAppear {
                    isEditorFocused = true
                }
                .onChange(of: note.content) {
                    note.detectKeyword()
                }
        }
    }
}
