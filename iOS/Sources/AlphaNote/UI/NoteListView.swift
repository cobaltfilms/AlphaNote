import SwiftUI

struct NoteListView: View {
    @ObservedObject var store: NoteStore
    @Binding var selectedNoteID: Int64?
    @State private var showNewNote = false

    var body: some View {
        List {
            ForEach(store.notes) { note in
                NavigationLink(value: note.id) {
                    NoteRowView(note: note)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteNote(note)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        store.togglePin(note)
                    } label: {
                        Label(note.isPinned ? "Désépingler" : "Épingler",
                              systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("AlphaNote")
        .navigationDestination(for: Int64.self) { id in
            if let note = store.note(byID: id) {
                NoteEditorView(note: note, store: store)
            }
        }
        .onAppear { store.loadNotes() }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { store.addNote() }) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .padding(16)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
    }
}
