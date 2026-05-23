import SwiftUI

struct PlainNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore
    @AppStorage("fontSize") private var fontSize: Double = 14

    var body: some View {
        TextEditor(text: $note.content)
            .font(.system(size: fontSize))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
    }
}
