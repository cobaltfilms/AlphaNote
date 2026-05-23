import SwiftUI

struct ContentView: View {
    @ObservedObject var store: NoteStore
    @Binding var selectedNoteID: Int64?

    @State private var showSidebar = false
    @State private var showSettings = false

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView {
                NoteListSidebar(store: store, selectedNoteID: $selectedNoteID)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gear")
                            }
                        }
                    }
            } detail: {
                if let id = selectedNoteID,
                   let note = store.note(byID: id) {
                    NoteEditorView(note: note, store: store)
                } else {
                    ContentUnavailableView(
                        "AlphaNote",
                        systemImage: "note.text",
                        description: Text("Sélectionne une note ou crées-en une nouvelle.")
                    )
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        } else {
            NavigationStack {
                NoteListView(store: store, selectedNoteID: $selectedNoteID)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
                                Button(action: { store.addNote() }) {
                                    Image(systemName: "plus")
                                }
                                Button(action: { showSettings = true }) {
                                    Image(systemName: "gear")
                                }
                            }
                        }
                    }
                    .navigationDestination(for: Int64.self) { id in
                        if let note = store.note(byID: id) {
                            NoteEditorView(note: note, store: store)
                        }
                    }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - iPad Sidebar
struct NoteListSidebar: View {
    @ObservedObject var store: NoteStore
    @Binding var selectedNoteID: Int64?

    var body: some View {
        List(store.notes, selection: $selectedNoteID) { note in
            NoteRowView(note: note)
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
        .navigationTitle("AlphaNote")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { store.addNote() }) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .onAppear { store.loadNotes() }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(note.effectiveTitle.isEmpty ? "Nouvelle note" : note.effectiveTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
