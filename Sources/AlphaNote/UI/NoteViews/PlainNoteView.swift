import SwiftUI

struct PlainNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore
    @AppStorage("fontSize") private var fontSize: Double = 14
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        TextEditor(text: $note.content)
            .font(.system(size: fontSize))
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onAppear {
                isEditorFocused = true
            }
            .onChange(of: note.content) {
                note.detectKeyword()
            }
    }
}
