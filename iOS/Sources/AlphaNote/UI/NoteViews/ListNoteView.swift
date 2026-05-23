import SwiftUI

struct ListNoteView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore

    var body: some View {
        TextEditor(text: $note.content)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
    }
}
