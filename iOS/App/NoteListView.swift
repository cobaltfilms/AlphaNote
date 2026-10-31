import SwiftUI

/// Liste des notes : Épinglées, Notes, puis Archives repliables, dans l'ordre
/// du NoteStore (épinglées, puis date de création décroissante). Même contenu
/// que NoteListScreen.kt sur Android.
struct NoteListView: View {
    @EnvironmentObject private var store: NoteStore
    @ObservedObject private var sync = SyncEngine.shared
    @AppStorage(AppSettings.autoCleanupKey) private var autoCleanup = true
    @AppStorage(AppSettings.confirmDeleteKey) private var confirmDelete = true

    @Binding var showSettings: Bool
    @State private var showEditor = false
    @State private var showArchives = false
    @State private var search = ""
    @State private var renaming: Note?
    @State private var renameDraft = ""
    @State private var deleting: Note?

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    let pinned = store.notes.filter(\.isPinned)
                    let others = store.notes.filter { !$0.isPinned }
                    if !pinned.isEmpty {
                        Section("Épinglées") { rows(pinned) }
                    }
                    Section(pinned.isEmpty ? "" : "Notes") { rows(others) }
                    if !store.archivedNotes.isEmpty {
                        Section {
                            DisclosureGroup("Archives · \(store.archivedNotes.count)", isExpanded: $showArchives) {
                                rows(store.archivedNotes.sorted { $0.updatedAt > $1.updatedAt })
                            }
                        }
                    }
                    Section {
                        Text(countLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    searchResults
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.windowColor.ignoresSafeArea())
            .navigationTitle("AlphaNote")
            .searchable(text: $search, prompt: "Rechercher")
            .task(id: search) {
                let query = search.trimmingCharacters(in: .whitespaces)
                guard query.count >= 2 else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await store.semanticSearch(query: query)
            }
            .refreshable { SyncEngine.shared.runManualSync() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    syncIndicator
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Bouton flottant, comme le FAB d'Android.
                Button {
                    store.addNote()
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.contentColor)
                        .frame(width: 58, height: 58)
                        .background(Palette.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
                .accessibilityLabel("Nouvelle note")
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
            .navigationDestination(isPresented: $showEditor) {
                NoteEditScreen()
            }
            .alert("Renommer la note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titre", text: $renameDraft)
                Button("Renommer") {
                    if let note = renaming { store.renameNote(note, to: renameDraft) }
                    renaming = nil
                }
                Button("Annuler", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Supprimer cette note ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let note = deleting { delete(note) }
                    deleting = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast, !showEditor {
                ToastView(toast: toast).padding(.bottom, 90)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .onAppear {
            // Comme Android : les notes vides disparaissent à l'ouverture de la liste.
            if autoCleanup { store.deleteEmptyNotes() }
        }
        .onChange(of: showEditor) { _, isShown in
            // Retour à la liste : les notes vides disparaissent (réglage).
            if !isShown, autoCleanup { store.deleteEmptyNotes() }
        }
    }

    private var countLabel: String {
        let count = store.notes.count
        return count == 1 ? "1 note" : "\(count) notes"
    }

    // MARK: - Lignes

    @ViewBuilder
    private func rows(_ notes: [Note]) -> some View {
        ForEach(notes, id: \.uuid) { note in
            row(note)
        }
    }

    private func row(_ note: Note) -> some View {
        let mode = NoteMode(rawValue: note.keyword) ?? .plain
        return Button { open(note) } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Palette.modeColor(mode))
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(NoteFormatting.displayTitle(note))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.textColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(NoteFormatting.shortDate(note.updatedAt))
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryColor)
                    }
                    Text(NoteFormatting.preview(for: note))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryColor)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Palette.contentColor)
        .contextMenu { menu(for: note) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { requestDelete(note) } label: { Label("Supprimer", systemImage: "trash") }
            if note.archived {
                Button { store.unarchiveNote(note) } label: { Label("Désarchiver", systemImage: "tray.and.arrow.up") }
            } else {
                Button { store.archiveNote(note) } label: { Label("Archiver", systemImage: "archivebox") }
                    .tint(Palette.accent2Color)
            }
        }
        .swipeActions(edge: .leading) {
            if !note.archived {
                Button { store.togglePin(note) } label: {
                    Label(note.isPinned ? "Désépingler" : "Épingler", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(Palette.accentColor)
            }
        }
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        if note.archived {
            Button { store.unarchiveNote(note) } label: { Label("Désarchiver", systemImage: "tray.and.arrow.up") }
        } else {
            Button { store.togglePin(note) } label: {
                Label(note.isPinned ? "Désépingler" : "Épingler", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameDraft = note.title.isEmpty ? NoteFormatting.displayTitle(note) : note.title
                renaming = note
            } label: { Label("Renommer", systemImage: "pencil") }
            Button { store.duplicateNote(note) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button { store.archiveNote(note) } label: { Label("Archiver", systemImage: "archivebox") }
        }
        Button(role: .destructive) { requestDelete(note) } label: { Label("Supprimer", systemImage: "trash") }
    }

    // MARK: - Recherche

    /// Correspondances exactes (titre, contenu) d'abord, puis les notes proches
    /// au sens de la recherche sémantique locale.
    @ViewBuilder
    private var searchResults: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = store.notes + store.archivedNotes
        let exact = all.filter {
            $0.content.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
        }
        let exactIDs = Set(exact.map(\.uuid))
        let liveByUUID = Dictionary(all.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let semantic = store.semanticSearchResults.compactMap { liveByUUID[$0.note.uuid] }.filter { !exactIDs.contains($0.uuid) }

        if exact.isEmpty && semantic.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        }
        if !exact.isEmpty {
            Section("Correspondances") { rows(exact) }
        }
        if !semantic.isEmpty, query.count >= 2 {
            Section("Notes proches") { rows(semantic) }
        }
    }

    // MARK: - Synchro

    @ViewBuilder
    private var syncIndicator: some View {
        switch sync.status {
        case .syncing:
            ProgressView()
        case .error(let message):
            Button { store.showToast(message, symbol: "exclamationmark.icloud") } label: {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
            }
            .accessibilityLabel("Erreur de synchronisation")
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func open(_ note: Note) {
        guard let id = note.id else { return }
        if note.archived {
            store.unarchiveNote(note)
        }
        store.selectNote(id: id)
        showEditor = true
    }

    private func requestDelete(_ note: Note) {
        if confirmDelete, !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleting = note
        } else {
            delete(note)
        }
    }

    private func delete(_ note: Note) {
        for name in NoteAttachments.names(in: note.content) {
            NoteAttachments.remove(noteUUID: note.uuid, name: name)
        }
        store.deleteNote(note)
    }
}
