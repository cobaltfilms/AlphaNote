import SwiftUI
import AppKit

/// Vue principale : une surface d'écriture, une barre d'outils minimale, la
/// liste des notes en volet superposé (⌥⌘L), la demande en langage naturel en
/// champ éphémère (⌘K) et un toast pour les retours. Pas de compteur, pas de
/// panneau permanent : l'écran appartient au texte.
struct NoteListView: View {
    @StateObject fileprivate var store = NoteStore()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @ObservedObject private var vault = VaultKeyring.shared

    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("listCheckTrigger") private var listCheckTrigger: String = "/x"
    @AppStorage(AppDelegate.autoCleanupKey) private var autoCleanup = true

    @AppStorage(NoteWindowController.sidebarVisibleKey) private var isSidebarVisible = false
    @AppStorage(ColorTheme.storageKey) private var colorTheme = ColorTheme.or.rawValue
    @State private var isCommandVisible = false
    @State private var showArchived = false
    @State private var searchQuery = ""
    @State private var commandDraft = ""
    @State private var isRouting = false
    @State private var renamingNote: Note?
    @State private var renameDraft = ""
    @State private var showMicPermissionAlert = false
    @State private var confirmDelete: Note?

    @FocusState private var isSearchFocused: Bool
    @FocusState private var isCommandFocused: Bool

    var body: some View {
        // Les couleurs du thème sont lues à la création des vues : changer de
        // thème reconstruit l'arbre (les notes et l'état ci-dessus restent).
        mainLayers
            .id(colorTheme)
            .tint(Palette.accentColor)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSidebarVisible)
            .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isCommandVisible)
            .animation(.easeInOut(duration: 0.2), value: store.toast)
            .onAppear { store.loadNotes() }
            .modifier(NotificationHandlers(view: self))
            .onChange(of: speechRecognizer.transcript) { _, newValue in
                if !newValue.isEmpty { commandDraft = newValue }
            }
            .onChange(of: speechRecognizer.isListening) { _, listening in
                if !listening, !commandDraft.isEmpty, !isRouting { submitCommand() }
            }
            .sheet(item: $renamingNote) { note in renameSheet(for: note) }
            .alert("Supprimer cette note ?", isPresented: deleteAlertBinding, presenting: confirmDelete) { note in
                Button("Supprimer", role: .destructive) { store.deleteNote(note) }
                Button("Annuler", role: .cancel) {}
            } message: { note in
                Text("« \(displayTitle(note)) » sera supprimée. Les notes vides se suppriment sans confirmation.")
            }
            .alert("Reconnaissance vocale", isPresented: $showMicPermissionAlert) {
                Button("Ouvrir les Réglages Système") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("AlphaNote a besoin du microphone et de la reconnaissance vocale. Activez-les dans Réglages Système › Confidentialité.")
            }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
    }

    /// Deux colonnes : le volet des notes (optionnel, persistant) pousse
    /// l'éditeur au lieu de le recouvrir ; la demande ⌘K et le toast flottent
    /// uniquement au-dessus de la colonne éditeur.
    private var mainLayers: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebarPane
                    .frame(width: Self.sidebarWidth)
                    .transition(.move(edge: .leading))
                Rectangle()
                    .fill(Palette.lineColor)
                    .frame(width: 1)
            }
            editorColumn
        }
        .background(Palette.contentColor)
        .ignoresSafeArea()
    }

    private static let sidebarWidth: CGFloat = 260

    private var editorColumn: some View {
        ZStack(alignment: .top) {
            Palette.contentColor

            VStack(spacing: 0) {
                topBar
                editorArea
            }

            if isCommandVisible {
                commandField
                    .padding(.top, 44)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            toastView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Les commandes de menu et de l'AppDelegate arrivent par notifications.
    private struct NotificationHandlers: ViewModifier {
        let view: NoteListView

        func body(content: Content) -> some View {
            let center = NotificationCenter.default
            content
                .onReceive(center.publisher(for: .alphaNoteCreateNote)) { _ in view.store.addNote(); view.closeOverlays() }
                .onReceive(center.publisher(for: .alphaNoteToggleSidebar)) { _ in view.toggleSidebar() }
                .onReceive(center.publisher(for: .alphaNoteFocusSearch)) { _ in view.openSearch() }
                .onReceive(center.publisher(for: .alphaNoteToggleCommandField)) { _ in view.toggleCommandField() }
                .onReceive(center.publisher(for: .alphaNoteConvertToList)) { _ in view.store.convertCurrentNoteToList() }
                .onReceive(center.publisher(for: .alphaNoteNavigateNext)) { _ in view.store.navigateNext() }
                .onReceive(center.publisher(for: .alphaNoteNavigatePrevious)) { _ in view.store.navigatePrevious() }
                .onReceive(center.publisher(for: .alphaNoteTogglePin)) { _ in view.togglePinCurrent() }
                .onReceive(center.publisher(for: .alphaNoteArchiveCurrent)) { _ in view.archiveCurrent() }
                .onReceive(center.publisher(for: .alphaNoteDeleteCurrent)) { _ in view.deleteCurrent() }
                .onReceive(center.publisher(for: .alphaNoteSetMode)) { notification in view.setMode(notification.object as? NoteMode) }
                .onReceive(center.publisher(for: .alphaNoteDidSync)) { _ in view.store.flushPendingSaves(); view.store.loadNotes() }
                .onReceive(center.publisher(for: .alphaNoteWindowWillHide)) { _ in view.windowWillHide() }
        }
    }

    fileprivate func openSearch() {
        isSidebarVisible = true
        DispatchQueue.main.async { isSearchFocused = true }
    }

    fileprivate func togglePinCurrent() {
        if let note = store.currentNote { store.togglePin(note) }
    }

    fileprivate func archiveCurrent() {
        guard let note = store.currentNote else { return }
        store.archiveNote(note)
        store.showToast("Note archivée", symbol: "archivebox")
    }

    fileprivate func deleteCurrent() {
        if let note = store.currentNote { requestDelete(note) }
    }

    fileprivate func setMode(_ mode: NoteMode?) {
        guard let mode, let note = store.currentNote else { return }
        store.setMode(mode, for: note)
    }

    fileprivate func windowWillHide() {
        store.flushPendingSaves()
        if autoCleanup { store.deleteEmptyNotes() }
        closeOverlays()
    }

    // MARK: - Barre supérieure

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { toggleSidebar() } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryColor)
            .help("Liste des notes (⌥⌘L)")

            if let note = store.currentNote {
                HStack(spacing: 6) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.accentColor)
                    }
                    Text(displayTitle(note))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryColor)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginRename(note) }
            }

            Spacer(minLength: 8)

            if let note = store.currentNote {
                modeChip(for: note)
                noteMenu(for: note)
            }

            Button { store.addNote(); closeOverlays() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryColor)
            .help("Nouvelle note (⌥⌘N)")
        }
        .padding(.leading, isSidebarVisible ? 14 : 76) // feux tricolores
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(Palette.windowColor)
    }

    private func modeChip(for note: Note) -> some View {
        let mode = NoteMode(rawValue: note.keyword) ?? .plain
        return Menu {
            ForEach(NoteMode.allCases, id: \.self) { candidate in
                Button {
                    store.setMode(candidate, for: note)
                } label: {
                    Label(candidate.title, systemImage: candidate.symbol)
                }
                .disabled(candidate == mode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(mode.label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(ModePalette.foreground(mode))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(ModePalette.background(mode)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Mode de la note — la première ligne (math, list, code, timer) le change aussi")
    }

    private func noteMenu(for note: Note) -> some View {
        Menu {
            Button { toggleCommandField() } label: { Label("Demande en langage naturel…", systemImage: "sparkles") }
            Divider()
            Button { store.togglePin(note) } label: {
                Label(note.isPinned ? "Désépingler" : "Épingler", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button { beginRename(note) } label: { Label("Renommer…", systemImage: "pencil") }
            Button { store.duplicateNote(note) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button { copyNote(note) } label: { Label("Copier le contenu", systemImage: "doc.on.doc") }
            if note.isVault, vault.isUnlocked {
                Button { vault.lockNow() } label: { Label("Verrouiller le coffre", systemImage: "lock") }
            }
            Divider()
            Button { store.archiveNote(note); store.showToast("Note archivée", symbol: "archivebox") } label: {
                Label("Archiver", systemImage: "archivebox")
            }
            Button(role: .destructive) { requestDelete(note) } label: { Label("Supprimer", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Zone d'édition

    @ViewBuilder
    private var editorArea: some View {
        if let note = store.currentNote {
            ZStack {
                if note.keyword == "timer" {
                    timerView(for: note)
                        .id(note.uuid)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if note.isVault, !vault.isUnlocked {
                    // Note sécurisée, coffre fermé (ou pas encore de mot de
                    // passe : la note attend en mémoire d'être chiffrée).
                    VaultLockView(title: note.effectiveTitle)
                        .environmentObject(store)
                        .id(note.uuid)
                } else {
                    NoteEditorView(
                        text: contentBinding(for: note),
                        mode: NoteMode(rawValue: note.keyword) ?? .plain,
                        fontSize: fontSize,
                        checkTrigger: listCheckTrigger,
                        onEscape: handleEscape
                    )
                    .id(note.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                TrackpadSwipeMonitorView(
                    onSwipeLeft: { store.navigateNext() },
                    onSwipeRight: { store.navigatePrevious() }
                )
                .allowsHitTesting(false)
            }
        } else {
            Spacer()
        }
    }

    private func timerView(for note: Note) -> TimerNoteView {
        let parameters = store.timerParameters(for: note)
        let session = TimerRegistry.shared.session(for: note.uuid, defaultMode: parameters.mode, defaultSeconds: parameters.seconds)
        return TimerNoteView(session: session) { mode, seconds in
            store.updateTimerLine(noteID: note.id, mode: mode, seconds: seconds)
        }
    }

    private func contentBinding(for note: Note) -> Binding<String> {
        Binding(
            get: {
                guard let id = note.id, let current = store.notes.first(where: { $0.id == id }) else {
                    return store.plaintext(of: note) ?? ""
                }
                // Note sécurisée : déchiffrée pour l'affichage seulement.
                return store.plaintext(of: current) ?? ""
            },
            set: { newValue in
                guard let id = note.id, var current = store.notes.first(where: { $0.id == id }),
                      store.plaintext(of: current) != newValue else { return }
                current.content = newValue
                store.edit(current)
            }
        )
    }

    // MARK: - Champ de demande (⌘K)

    private var commandField: some View {
        let preview = KeywordIntentRouter.classify(commandDraft, noteKeyword: store.currentNote?.keyword)
        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accentColor)

            TextField("Demande : « minuteur 25 min », « courses : pain, lait », « 12 km to mi »…", text: $commandDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isCommandFocused)
                .disabled(isRouting)
                .onSubmit(submitCommand)
                .onExitCommand { closeCommandField() }

            if !commandDraft.trimmingCharacters(in: .whitespaces).isEmpty, preview != .plain {
                Text("\(preview.label) ?")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ModePalette.foreground(preview))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(ModePalette.background(preview)))
            }

            if isRouting || speechRecognizer.isListening {
                ProgressView().controlSize(.small)
            }

            Button {
                Task {
                    if speechRecognizer.isListening {
                        speechRecognizer.stopListening()
                    } else {
                        do { try await speechRecognizer.startListening() } catch { showMicPermissionAlert = true }
                    }
                }
            } label: {
                Image(systemName: speechRecognizer.isListening ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(speechRecognizer.isListening ? Color(nsColor: Palette.timer) : Palette.secondaryColor)
                    .symbolEffect(.pulse, isActive: speechRecognizer.isListening)
            }
            .buttonStyle(.plain)
            .help(speechRecognizer.isListening ? "Arrêter l'écoute" : "Dicter")

            Button { closeCommandField() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryColor.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.fieldColor)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.accentColor.opacity(0.6), lineWidth: 1)
        )
        .onAppear { DispatchQueue.main.async { isCommandFocused = true } }
    }

    private func submitCommand() {
        guard !isRouting else { return }
        let question = commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { closeCommandField(); return }
        Task {
            isRouting = true
            await store.routeQuestion(question)
            isRouting = false
            commandDraft = ""
            closeCommandField()
        }
    }

    fileprivate func toggleCommandField() {
        if isCommandVisible { closeCommandField() } else { isCommandVisible = true }
    }

    private func closeCommandField() {
        if speechRecognizer.isListening { speechRecognizer.stopListening() }
        isCommandVisible = false
        refocusEditor()
    }

    // MARK: - Volet des notes

    private var sidebarPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryColor)
                TextField("Rechercher", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
                    .onSubmit { openFirstResultOrSearch() }
                    .onExitCommand { closeSidebar() }
                    .onMoveCommand { direction in moveSelection(direction) }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        store.semanticSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondaryColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fieldColor))
            .padding(.horizontal, 12)
            .padding(.top, 44) // sous les feux tricolores
            .padding(.bottom, 8)
            .onChange(of: searchQuery) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.semanticSearchResults = []
                } else {
                    Task { await store.semanticSearch(query: newValue) }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let pinned = filteredNotes.filter(\.isPinned)
                        let others = filteredNotes.filter { !$0.isPinned }

                        if !pinned.isEmpty {
                            sectionHeader("Épinglées", systemImage: "pin.fill")
                            ForEach(pinned, id: \.id) { note in noteRow(note, archived: false) }
                        }
                        if !others.isEmpty {
                            if !pinned.isEmpty { sectionHeader("Notes", systemImage: nil) }
                            ForEach(others, id: \.id) { note in noteRow(note, archived: false) }
                        }
                        if filteredNotes.isEmpty {
                            Text(searchQuery.isEmpty ? "Aucune note" : "Aucun résultat")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondaryColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }

                        if !store.archivedNotes.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { showArchived.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Archives · \(store.archivedNotes.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Palette.secondaryColor)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if showArchived {
                                ForEach(store.archivedNotes, id: \.id) { note in noteRow(note, archived: true) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .onChange(of: store.currentIndex) { _, _ in
                    if let id = store.currentNote?.id {
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(store.notes.count) note\(store.notes.count > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryColor)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .alphaNoteOpenSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondaryColor)
                .help("Réglages (⌘,)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
        .background(Palette.sidebarColor)
    }

    /// ↑ / ↓ dans le champ de recherche : change la note sélectionnée sans
    /// quitter le volet (ordre d'affichage : épinglées puis les autres).
    private func moveSelection(_ direction: MoveCommandDirection) {
        let ordered = filteredNotes.filter(\.isPinned) + filteredNotes.filter { !$0.isPinned }
        guard !ordered.isEmpty else { return }
        let currentID = store.currentNote?.id
        let index = ordered.firstIndex(where: { $0.id == currentID })
        let target: Int
        switch direction {
        case .down: target = index.map { min($0 + 1, ordered.count - 1) } ?? 0
        case .up: target = index.map { max($0 - 1, 0) } ?? 0
        default: return
        }
        if let id = ordered[target].id { store.selectNote(id: id) }
    }

    /// Entrée dans la recherche : ouvre le premier résultat (déjà filtré au fil
    /// de la frappe) et rend le focus à l'éditeur.
    private func openFirstResultOrSearch() {
        let ordered = filteredNotes.filter(\.isPinned) + filteredNotes.filter { !$0.isPinned }
        if let first = ordered.first, let id = first.id {
            store.selectNote(id: id)
            refocusEditor()
        } else {
            Task { await store.semanticSearch(query: searchQuery) }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
            Spacer()
        }
        .foregroundStyle(Palette.secondaryColor)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func noteRow(_ note: Note, archived: Bool) -> some View {
        let selected = !archived && note.id == store.currentNote?.id
        let mode = NoteMode(rawValue: note.keyword) ?? .plain
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ModePalette.foreground(mode))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .opacity(mode == .plain ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayTitle(note))
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Palette.textColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.shortDate(note.updatedAt))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.secondaryColor.opacity(0.85))
                        .monospacedDigit()
                }
                Text(preview(for: note))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Palette.selectionColor : Color.clear)
        )
        .opacity(archived ? 0.7 : 1)
        .id(note.id)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if archived {
                store.unarchiveNote(note)
            } else if let id = note.id {
                store.selectNote(id: id)
            }
            refocusEditor()
        }
        .contextMenu {
            Button(note.isPinned ? "Désépingler" : "Épingler") { store.togglePin(note) }
            Button("Renommer…") { beginRename(note) }
            Button("Dupliquer") { store.duplicateNote(note) }
            if archived {
                Button("Désarchiver") { store.unarchiveNote(note) }
            } else {
                Button("Archiver") { store.archiveNote(note) }
            }
            Divider()
            Button("Supprimer", role: .destructive) { requestDelete(note) }
        }
    }

    private var filteredNotes: [Note] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.notes }
        let lower = query.lowercased()
        // Note sécurisée : seul son titre est cherchable.
        let textMatches = store.notes.filter {
            ($0.isVault ? $0.effectiveTitle : $0.content).lowercased().contains(lower) || $0.title.lowercased().contains(lower)
        }
        let semanticIDs = Set(store.semanticSearchResults.map(\.note.uuid))
        let textIDs = Set(textMatches.map(\.uuid))
        let semanticOnly = store.notes.filter { semanticIDs.contains($0.uuid) && !textIDs.contains($0.uuid) }
        return textMatches + semanticOnly
    }

    fileprivate func toggleSidebar() {
        if isSidebarVisible { closeSidebar() } else {
            isCommandVisible = false
            isSidebarVisible = true
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    private func closeSidebar() {
        isSidebarVisible = false
        refocusEditor()
    }

    /// Le volet est un état persistant, pas une superposition : seuls le champ
    /// ⌘K et la dictée se ferment ici.
    fileprivate func closeOverlays() {
        if speechRecognizer.isListening { speechRecognizer.stopListening() }
        isCommandVisible = false
    }

    private func handleEscape() {
        if isCommandVisible {
            closeCommandField()
        } else {
            NotificationCenter.default.post(name: .alphaNoteHideWindow, object: nil)
        }
    }

    private func refocusEditor() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let textView = firstTextView(in: window.contentView) else { return }
            window.makeFirstResponder(textView)
        }
    }

    private func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NoteTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast = store.toast {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accentColor)
                    Text(toast.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textColor)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Palette.fieldColor)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                )
                .overlay(Capsule(style: .continuous).stroke(Palette.lineColor, lineWidth: 1))
                .padding(.bottom, 16)
                .onTapGesture { store.toast = nil }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Divers

    /// Date courte façon liste de notes : heure si aujourd'hui, « hier »,
    /// jour de la semaine dans les 7 jours, sinon « 23 oct. ».
    static func shortDate(_ date: Date, now: Date = Date()) -> String {
        NoteFormatting.shortDate(date, now: now)
    }

    private func displayTitle(_ note: Note) -> String {
        NoteFormatting.displayTitle(note)
    }

    private func preview(for note: Note) -> String {
        NoteFormatting.preview(for: note)
    }

    private func beginRename(_ note: Note) {
        renameDraft = note.title.isEmpty ? displayTitle(note) : note.title
        renamingNote = note
    }

    fileprivate func requestDelete(_ note: Note) {
        if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.deleteNote(note)
        } else {
            confirmDelete = note
        }
    }

    private func copyNote(_ note: Note) {
        NSPasteboard.general.clearContents()
        guard let text = store.plaintext(of: note) else {
            store.showToast("Ouvre le coffre pour copier cette note.", symbol: "lock.fill")
            return
        }
        NSPasteboard.general.setString(text, forType: .string)
        store.showToast("Contenu copié", symbol: "doc.on.doc")
    }

    private func renameSheet(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renommer la note").font(.headline)
            TextField("Nom (vide = première ligne)", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.renameNote(note, to: renameDraft); renamingNote = nil }
            HStack {
                Spacer()
                Button("Annuler") { renamingNote = nil }
                Button("Enregistrer") {
                    store.renameNote(note, to: renameDraft)
                    renamingNote = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

// MARK: - Swipe trackpad

private struct TrackpadSwipeMonitorView: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        private weak var view: NSView?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var didTrigger = false
        private let threshold: CGFloat = 110
        private let dominance: CGFloat = 1.4

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        deinit { detach() }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            reset()
        }

        private func handle(_ event: NSEvent) {
            guard let hostWindow = view?.window, event.window === hostWindow else { return }
            if event.phase == .began { reset() }

            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let ended = event.phase == .ended || event.phase == .cancelled
                || event.momentumPhase == .ended || event.momentumPhase == .cancelled

            guard abs(dx) > 0.5, abs(dx) > abs(dy) * dominance else {
                if ended { reset() }
                return
            }
            accumulated += dx
            if !didTrigger, abs(accumulated) >= threshold {
                didTrigger = true
                accumulated > 0 ? onSwipeRight() : onSwipeLeft()
            }
            if ended { reset() }
        }

        private func reset() {
            accumulated = 0
            didTrigger = false
        }
    }
}

extension Notification.Name {
    static let alphaNoteCreateNote = Notification.Name("alphaNoteCreateNote")
    static let alphaNoteToggleSidebar = Notification.Name("alphaNoteToggleSidebar")
    static let alphaNoteFocusSearch = Notification.Name("alphaNoteFocusSearch")
    static let alphaNoteToggleCommandField = Notification.Name("alphaNoteToggleCommandField")
    static let alphaNoteConvertToList = Notification.Name("alphaNoteConvertToList")
    static let alphaNoteNavigateNext = Notification.Name("alphaNoteNavigateNext")
    static let alphaNoteNavigatePrevious = Notification.Name("alphaNoteNavigatePrevious")
    static let alphaNoteTogglePin = Notification.Name("alphaNoteTogglePin")
    static let alphaNoteArchiveCurrent = Notification.Name("alphaNoteArchiveCurrent")
    static let alphaNoteDeleteCurrent = Notification.Name("alphaNoteDeleteCurrent")
    static let alphaNoteSetMode = Notification.Name("alphaNoteSetMode")
    static let alphaNoteOpenHelpCenter = Notification.Name("alphaNoteOpenHelpCenter")
    static let alphaNoteCheckForUpdates = Notification.Name("alphaNoteCheckForUpdates")
    static let alphaNoteOpenSettings = Notification.Name("alphaNoteOpenSettings")
}
