import SwiftUI
import AppKit

struct NoteListView: View {
    @StateObject private var store = NoteStore()
    @State private var isSidebarVisible = true
    @State private var showArchived = false
    @State private var renamingNote: Note?
    @State private var renameDraft = ""
    @State private var semanticQuery = ""
    @State private var questionDraft = ""
    @State private var perNoteQuestionDraft: [Int64: String] = [:]
    @State private var lastRoutedQuestion = ""
    @State private var isAnswering = false
    @State private var showMicPermissionAlert = false
    @FocusState private var isAIQuestionFocused: Bool
    @StateObject private var speechRecognizer = SpeechRecognizer()

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebar
                    Divider()
                }

                content
            }
        }
        .onAppear {
            store.loadNotes()
            syncRightAIPanelWithCurrentNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .alphaNoteCreateNote)) { _ in
            store.addNote()
            isSidebarVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .alphaNoteToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                isSidebarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alphaNoteConvertToList)) { _ in
            store.convertCurrentNoteToList()
        }
        .onReceive(NotificationCenter.default.publisher(for: .alphaNoteDidSync)) { _ in
            Task { @MainActor in
                store.loadNotes()
            }
        }
        .onChange(of: store.currentNote?.id) {
            syncRightAIPanelWithCurrentNote()
        }
        .onChange(of: questionDraft) {
            guard let noteID = store.currentNote?.id else { return }
            perNoteQuestionDraft[noteID] = questionDraft
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            if !newValue.isEmpty {
                questionDraft = newValue
            }
        }
        .onChange(of: speechRecognizer.isListening) { _, isListening in
            if !isListening && !questionDraft.isEmpty && !isAnswering {
                askQuestionToCurrentNote()
            }
        }
        .alert("Reconnaissance vocale", isPresented: $showMicPermissionAlert) {
            Button("Ouvrir les Préférences Système") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("AlphaNote a besoin d'accéder au microphone et à la reconnaissance vocale. Veuillez activer ces permissions dans les Préférences Système.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.addNote()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Nouvelle note")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Rechercher", text: $semanticQuery)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit {
                                Task { await store.semanticSearch(query: semanticQuery) }
                            }
                        if !semanticQuery.isEmpty {
                            Button {
                                semanticQuery = ""
                                store.semanticSearchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !semanticQuery.isEmpty && filteredNotes.isEmpty {
                        Text("Aucun résultat")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                    .padding(.bottom, 6)

                    ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note: note, index: store.notes.firstIndex(where: { $0.id == note.id }) ?? index, isArchived: false)
                    }

                    if !store.archivedNotes.isEmpty {
                        Divider().padding(.vertical, 2)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showArchived.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Archives (\(store.archivedNotes.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)

                        if showArchived {
                            ForEach(store.archivedNotes, id: \.id) { note in
                                noteRow(note: note, index: nil, isArchived: true)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 220)
        .sheet(item: $renamingNote) { note in
            renameSheet(for: note)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Afficher/Masquer la liste")

                Text(positionLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.addNote()
                } label: {
                    Label("Nouvelle note", systemImage: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 8) {
                ZStack(alignment: .trailing) {
                    TextField("Détection du mode — tape ou dicte, puis Entrée…", text: $questionDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.leading, 88)
                        .padding(.trailing, 12)
                        .padding(.vertical, 8)
                        .focused($isAIQuestionFocused)
                        .submitLabel(.send)
                        .disabled(isAnswering)
                        .onSubmit {
                            askQuestionToCurrentNote()
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isAIQuestionFocused
                                        ? Color.accentColor.opacity(0.95)
                                        : Color.accentColor.opacity(0.45),
                                    lineWidth: isAIQuestionFocused ? 1.8 : 1.0
                                )
                        )
                        .shadow(
                            color: Color.accentColor.opacity(isAIQuestionFocused ? 0.45 : 0.18),
                            radius: isAIQuestionFocused ? 12 : 6
                        )

                    HStack(spacing: 6) {
                        ForEach(detectedBadges, id: \.id) { badge in
                            intentBadge(badge)
                        }
                        Spacer()
                        micButton
                    }
                    .padding(.leading, 8)

                    if isAnswering {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 10)
                    } else if speechRecognizer.isListening {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.red)
                            .padding(.trailing, 10)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if let status = store.aiStatusMessage, !status.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: store.lastRoute?.source == .jev ? "sparkles" : "text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            ZStack {
                if store.notes.isEmpty {
                    Text("No notes")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else if let note = store.currentNote {
                    ZStack {
                        store.viewForNote(note)
                            .id(note.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        TrackpadSwipeMonitorView(
                            onSwipeLeft: { store.navigateNext() },
                            onSwipeRight: { store.navigatePrevious() }
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var positionLabel: String {
        guard !store.notes.isEmpty else { return "0 / 0" }
        return "\(store.currentIndex + 1) / \(store.notes.count)"
    }

    private func askQuestionToCurrentNote() {
        guard !isAnswering else { return }
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        Task {
            isAnswering = true
            lastRoutedQuestion = question
            await store.routeQuestion(question)
            isAnswering = false
        }
    }

    @ViewBuilder
    private var micButton: some View {
        Button {
            Task {
                if speechRecognizer.isListening {
                    speechRecognizer.stopListening()
                } else {
                    do {
                        try await speechRecognizer.startListening()
                    } catch {
                        showMicPermissionAlert = true
                    }
                }
            }
        } label: {
            Image(systemName: speechRecognizer.isListening ? "waveform.circle.fill" : "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(speechRecognizer.isListening ? .red : .secondary)
                .symbolEffect(.pulse, isActive: speechRecognizer.isListening)
        }
        .buttonStyle(.plain)
        .help(speechRecognizer.isListening ? "Arrêter l'écoute" : "Dictée vocale")
        .disabled(isAnswering)
    }

    private struct IntentBadgeSpec {
        let id: String
        var label: String
        let foreground: Color
        let background: Color
    }

    private var detectedBadges: [IntentBadgeSpec] {
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return [] }
        let keyword = store.currentNote?.keyword

        if let route = store.lastRoute,
           store.aiStatusMessage != nil,
           question == lastRoutedQuestion {
            var spec = badgeSpec(for: route.mode)
            spec.label = "\(route.mode.label) · \(route.source.label)"
            return [spec]
        }

        let preview = KeywordIntentRouter.classify(question, noteKeyword: keyword)
        guard preview != .plain else { return [] }
        var spec = badgeSpec(for: preview)
        spec.label = "\(preview.label) ?"
        return [spec]
    }

    @ViewBuilder
    private func intentBadge(_ spec: IntentBadgeSpec) -> some View {
        Text(spec.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(spec.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(spec.background)
            )
    }

    private func badgeSpec(for mode: NoteMode) -> IntentBadgeSpec {
        IntentBadgeSpec(
            id: mode.rawValue,
            label: mode.label,
            foreground: ModePalette.foreground(mode),
            background: ModePalette.background(mode)
        )
    }

    private func title(for note: Note, index: Int) -> String {
        let displayTitle = note.effectiveTitle
        if !displayTitle.isEmpty {
            return displayTitle
        }
        return "Note \(index + 1)"
    }

    private func preview(for note: Note) -> String {
        let source: String
        if note.keyword == "list" {
            let lines = note.content.components(separatedBy: .newlines)
            if let first = lines.first, ListModeFormatter.isListHeader(first) {
                source = Array(lines.dropFirst()).joined(separator: "\n")
            } else {
                source = note.content
            }
        } else {
            source = note.content
        }

        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Vide"
        }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    @ViewBuilder
    private func noteRow(note: Note, index: Int?, isArchived: Bool) -> some View {
        let selected = index.map { $0 == store.currentIndex } ?? false

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: note, index: index ?? 0))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(preview(for: note))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Renommer") {
                    renamingNote = note
                    renameDraft = title(for: note, index: index ?? 0)
                }
                Button("Dupliquer") {
                    store.duplicateNote(note)
                }
                if isArchived {
                    Button("Désarchiver") {
                        store.unarchiveNote(note)
                    }
                } else {
                    Button("Archiver") {
                        store.archiveNote(note)
                    }
                }
                Divider()
                Button("Supprimer", role: .destructive) {
                    store.deleteNote(note)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.primary.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isArchived ? 0.72 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            guard !isArchived else { return }
            if let noteID = note.id {
                store.selectNote(id: noteID)
            } else if let index {
                store.currentIndex = index
            }
        }
    }

    private func renameSheet(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renommer la note")
                .font(.headline)
            TextField("Nouveau nom", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annuler") {
                    renamingNote = nil
                }
                Button("Enregistrer") {
                    store.renameNote(note, to: renameDraft)
                    renamingNote = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private var filteredNotes: [Note] {
        let query = semanticQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.notes }
        let lower = query.lowercased()
        let textMatches = store.notes.filter { note in
            note.content.lowercased().contains(lower) ||
            note.title.lowercased().contains(lower)
        }
        let hitIDs = Set(store.semanticSearchResults.map { $0.note.id })
        if hitIDs.isEmpty {
            return textMatches
        }
        let textIDs = Set(textMatches.map { $0.id })
        let semanticOnly = store.notes.filter { hitIDs.contains($0.id) && !textIDs.contains($0.id) }
        var merged = textMatches
        for note in semanticOnly {
            merged.append(note)
        }
        let ordered = Set(merged.map { $0.id })
        return store.notes.filter { ordered.contains($0.id) }
    }

    private func syncRightAIPanelWithCurrentNote() {
        guard let noteID = store.currentNote?.id else {
            questionDraft = ""
            return
        }
        questionDraft = perNoteQuestionDraft[noteID] ?? ""
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct TrackpadSwipeMonitorView: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = false
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
        private var accumulatedHorizontalDelta: CGFloat = 0
        private var didTriggerForCurrentGesture = false

        private let horizontalThreshold: CGFloat = 100
        private let horizontalDominanceRatio: CGFloat = 1.35

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        deinit {
            detach()
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            resetGestureState()
        }

        private func handleScroll(_ event: NSEvent) {
            guard let hostWindow = view?.window,
                  event.window === hostWindow else {
                return
            }

            if event.phase == .began || event.momentumPhase == .began {
                resetGestureState()
            }

            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            guard abs(deltaX) > 0.5,
                  abs(deltaX) > abs(deltaY) * horizontalDominanceRatio else {
                if event.phase == .ended || event.phase == .cancelled ||
                    event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                    resetGestureState()
                }
                return
            }

            accumulatedHorizontalDelta += deltaX

            if !didTriggerForCurrentGesture,
               abs(accumulatedHorizontalDelta) >= horizontalThreshold {
                didTriggerForCurrentGesture = true
                if accumulatedHorizontalDelta > 0 {
                    onSwipeRight()
                } else {
                    onSwipeLeft()
                }
            }

            if event.phase == .ended || event.phase == .cancelled ||
                event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                resetGestureState()
            }
        }

        private func resetGestureState() {
            accumulatedHorizontalDelta = 0
            didTriggerForCurrentGesture = false
        }
    }
}

extension Notification.Name {
    static let alphaNoteCreateNote = Notification.Name("alphaNoteCreateNote")
    static let alphaNoteToggleSidebar = Notification.Name("alphaNoteToggleSidebar")
    static let alphaNoteConvertToList = Notification.Name("alphaNoteConvertToList")
    static let alphaNoteDidSync = Notification.Name("alphaNoteDidSync")
    static let alphaNoteOpenHelpCenter = Notification.Name("alphaNoteOpenHelpCenter")
    static let alphaNoteCheckForUpdates = Notification.Name("alphaNoteCheckForUpdates")
}
