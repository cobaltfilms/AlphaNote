import SwiftUI

struct PlainNoteView: View {
    @Binding var note: Note
    @AppStorage("fontSize") private var fontSize: Double = 14

    var body: some View {
        TextEditor(text: $note.content)
            .font(.system(size: fontSize))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onChange(of: note.content) {
                note.detectKeyword()
            }
    }
}