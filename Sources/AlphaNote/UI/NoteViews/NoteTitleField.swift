import SwiftUI

/// Titre de la note, modifiable sur place (macOS : barre du haut ; iOS : en
/// tête de la note). Vide = titre automatique (première ligne), affiché en
/// gris comme indication.
struct NoteTitleField: View {
    let note: Note
    var font: Font = .body.weight(.semibold)
    let onRename: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(NoteFormatting.displayTitle(note), text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .lineLimit(1)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { draft = note.title }
            .onChange(of: note.id) { _, _ in draft = note.title }
            .onChange(of: note.title) { _, title in if !focused { draft = title } }
            .accessibilityIdentifier("noteTitle")
            .help("Titre de la note — vide : la première ligne")
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != note.title else { return }
        onRename(trimmed)
    }
}
