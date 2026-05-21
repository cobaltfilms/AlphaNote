import SwiftUI
import AppKit

struct NoteListView: View {
    @StateObject private var store = NoteStore()
    @State private var isSidebarVisible = true
    @State private var showArchived = false
    @State private var renamingNote: Note?
    @State private var renameDraft = ""

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
            store.loadNotes()
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
                    ForEach(Array(store.notes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note: note, index: index, isArchived: false)
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

    private func title(for note: Note, index: Int) -> String {
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let lines = note.content.components(separatedBy: .newlines)
        if let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return firstNonEmpty.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
