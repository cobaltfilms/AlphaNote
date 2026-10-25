import Foundation
import SwiftUI

/// Message transitoire affiché en bas de la fenêtre (routage de mode, sync…).
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let symbol: String
}

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var archivedNotes: [Note] = []
    @Published var currentIndex: Int = 0

    // État IA — géré par AIStore, publié ici pour SwiftUI.
    @Published var isAIProcessing = false
    @Published var lastRoute: ModeDecision?
    @Published var aiStatusMessage: String?
    @Published var semanticSearchResults: [SemanticSearchHit] = []

    @Published var toast: Toast?

    @AppStorage("archivedNoteIDs") private var legacyArchivedNoteIDsStorage: String = "[]"
    @AppStorage("archivedIDsMigratedToDatabase") private var archivedIDsMigratedToDatabase: Bool = false
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false

    lazy var aiStore = AIStore(noteStore: self)

    /// Sauvegardes différées : une écriture SQLite par note au plus toutes les
    /// `saveDelay`, et jamais une par frappe.
    private var pendingNotes: [Int64: Note] = [:]
    private var pendingSaveTasks: [Int64: Task<Void, Never>] = [:]
    private let saveDelay: UInt64 = 400_000_000
    private var toastTask: Task<Void, Never>?

    var isAIEnabled: Bool { aiEnabled }

    var currentNote: Note? {
        guard !notes.isEmpty, currentIndex >= 0, currentIndex < notes.count else { return nil }
        return notes[currentIndex]
    }

    // MARK: - Chargement

    func loadNotes() {
        migrateLegacyArchiveIDsIfNeeded()
        reloadNotes()
        repairListNotesIfNeeded()
        let snapshot = notes + archivedNotes
        Task.detached(priority: .utility) {
            for note in snapshot where !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await SemanticSearchFeature().index(note: note)
            }
        }
    }

    // MARK: - Création

    @discardableResult
    func addNote(content: String = "") -> Note? {
        let created = Note.create(Note(content: content, position: nextPosition()))
        guard let createdID = created.id else {
            reloadNotes()
            return nil
        }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
        return created
    }

    func createNote(keyword: String, content: String) -> Bool {
        var note = Note(content: content, keyword: keyword, position: nextPosition())
        note = Note.create(note)
        guard let createdID = note.id else { return false }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
        return true
    }

    private func nextPosition() -> Int {
        ((notes + archivedNotes).map(\.position).max() ?? -1) + 1
    }

    // MARK: - Sélection

    func selectNote(id: Int64) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        flushPendingSaves()
        currentIndex = index
    }

    func navigateNext() {
        guard !notes.isEmpty else { addNote(); return }
        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: false) { return }
        flushPendingSaves()
        if currentIndex < notes.count - 1 {
            currentIndex += 1
        } else {
            addNote()
        }
    }

    func navigatePrevious() {
        guard !notes.isEmpty else { addNote(); return }
        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: true) { return }
        flushPendingSaves()
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    // MARK: - Édition

    /// Mise à jour en mémoire immédiate, écriture disque différée.
    func edit(_ note: Note) {
        var updated = note
        updated.detectKeyword()
        updated.updatedAt = Date()
        updated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
        replaceInMemory(updated)

        guard let id = updated.id else { return }
        pendingNotes[id] = updated
        pendingSaveTasks[id]?.cancel()
        pendingSaveTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.saveDelay ?? 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.persistPending(id: id) }
        }
    }

    /// Mise à jour immédiate (actions explicites : renommer, archiver, épingler…).
    func updateNote(_ note: Note) {
        var updated = note
        updated.detectKeyword()
        updated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
        if let id = updated.id {
            pendingSaveTasks[id]?.cancel()
            pendingSaveTasks[id] = nil
            pendingNotes[id] = nil
        }
        Note.update(updated)
        updated.updatedAt = Date()
        replaceInMemory(updated)
        SyncEngine.shared.notifyLocalChange()
        Task.detached(priority: .utility) { await SemanticSearchFeature().index(note: updated) }
    }

    func flushPendingSaves() {
        for id in Array(pendingNotes.keys) {
            pendingSaveTasks[id]?.cancel()
            persistPending(id: id)
        }
    }

    private func persistPending(id: Int64) {
        pendingSaveTasks[id] = nil
        guard let note = pendingNotes.removeValue(forKey: id) else { return }
        Note.update(note)
        SyncEngine.shared.notifyLocalChange()
        Task.detached(priority: .utility) { await SemanticSearchFeature().index(note: note) }
    }

    private func replaceInMemory(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else if let index = archivedNotes.firstIndex(where: { $0.id == note.id }) {
            archivedNotes[index] = note
        }
    }

    // MARK: - Actions sur une note

    func togglePin(_ note: Note) {
        var updated = note
        updated.isPinned.toggle()
        updateNote(updated)
        reloadNotes(selecting: currentNote?.id)
    }

    func archiveNote(_ note: Note) {
        var updated = note
        updated.archived = true
        updateNote(updated)
        let nextSelection = note.id == currentNote?.id ? adjacentNoteID(forDeletedNoteID: note.id) : currentNote?.id
        reloadNotes(selecting: nextSelection)
    }

    func unarchiveNote(_ note: Note) {
        var updated = note
        updated.archived = false
        updateNote(updated)
        reloadNotes(selecting: note.id)
    }

    func duplicateNote(_ note: Note) {
        flushPendingSaves()
        var duplicated = note
        duplicated.id = nil
        duplicated.uuid = UUID().uuidString.lowercased()
        duplicated.createdAt = Date()
        duplicated.updatedAt = Date()
        duplicated.archived = false
        duplicated.isPinned = false
        duplicated.isDeleted = false
        duplicated.deletedAt = nil
        duplicated.lastSyncedAt = nil
        duplicated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
        duplicated.aiSummary = ""
        duplicated.aiLastProcessedAt = nil
        duplicated.position = nextPosition()

        let created = Note.create(duplicated)
        guard let createdID = created.id else { reloadNotes(); return }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
    }

    func renameNote(_ note: Note, to newTitle: String) {
        var updated = note
        updated.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updateNote(updated)
    }

    func deleteNote(_ note: Note) {
        if let id = note.id {
            pendingSaveTasks[id]?.cancel()
            pendingSaveTasks[id] = nil
            pendingNotes[id] = nil
        }
        let nextSelection = note.id == currentNote?.id ? adjacentNoteID(forDeletedNoteID: note.id) : currentNote?.id
        Note.delete(note)
        TimerRegistry.shared.discard(noteUUID: note.uuid)
        Task.detached(priority: .utility) { await EmbeddingStore.shared.removeEmbedding(noteUUID: note.uuid) }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: nextSelection)
    }

    /// Nettoyage des notes vides (réglage « auto-cleanup »), déclenché quand la
    /// fenêtre se cache. La note courante vide est gardée si elle est seule.
    func deleteEmptyNotes() {
        flushPendingSaves()
        let empties = notes.filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !empties.isEmpty, empties.count < notes.count || notes.count > 1 else { return }
        let selectedID = currentNote.flatMap { current in
            empties.contains(where: { $0.id == current.id }) ? nil : current.id
        }
        for note in empties {
            Note.delete(note)
            TimerRegistry.shared.discard(noteUUID: note.uuid)
        }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: selectedID)
    }

    // MARK: - Modes

    /// Change le mode de la note courante en réécrivant sa première ligne.
    func setMode(_ mode: NoteMode, for note: Note) {
        var updated = note
        var lines = updated.content.components(separatedBy: .newlines)
        let firstTrimmed = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasHeader = Note.knownKeywords.contains(firstTrimmed.lowercased())
            || Note.knownKeywords.contains(firstTrimmed.split(separator: ":", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } ?? "")

        var suffix = ""
        if hasHeader, let colon = firstTrimmed.firstIndex(of: ":") {
            suffix = String(firstTrimmed[firstTrimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if hasHeader { lines.removeFirst() }

        switch mode {
        case .plain:
            break
        case .math, .list, .timer, .code:
            let header = suffix.isEmpty ? mode.rawValue : "\(mode.rawValue): \(suffix)"
            lines.insert(header, at: 0)
        }

        updated.content = lines.joined(separator: "\n")
        if mode == .list {
            updated.content = ListModeFormatter.normalizeForListMode(content: updated.content, forceListHeader: true)
        }
        if mode == .timer, lines.count == 1 {
            updated.content += "\ncountdown 10:00"
        }
        updateNote(updated)
    }

    func convertCurrentNoteToList() {
        guard let note = currentNote else { return }
        setMode(.list, for: note)
    }

    // MARK: - Toast

    func showToast(_ text: String, symbol: String = "info.circle", duration: TimeInterval = 4) {
        toastTask?.cancel()
        toast = Toast(text: text, symbol: symbol)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    // MARK: - IA (délégation à AIStore)

    func routeQuestion(_ question: String) async {
        flushPendingSaves()
        await aiStore.routeQuestion(question)
        if let message = aiStatusMessage {
            showToast(message, symbol: lastRoute?.source == .jev ? "sparkles" : "text.magnifyingglass")
        }
    }

    func semanticSearch(query: String) async {
        await aiStore.semanticSearch(query: query)
    }

    // MARK: - Minuteur

    func timerParameters(for note: Note) -> (mode: TimerSession.Mode, seconds: Int) {
        var mode: TimerSession.Mode = .countdown
        var seconds = 600
        for line in note.content.components(separatedBy: .newlines) {
            if let detected = TimerSession.Mode(keyword: line) { mode = detected }
            if let match = line.range(of: #"(\d+):(\d{1,2})"#, options: .regularExpression) {
                let parts = line[match].split(separator: ":")
                if parts.count == 2, let minutes = Int(parts[0]), let secs = Int(parts[1]) {
                    seconds = minutes * 60 + secs
                }
            }
        }
        return (mode, seconds)
    }

    /// Réglage du minuteur reporté dans la note (« countdown 4:30 ») : l'aperçu
    /// de la liste le montre, la synchro et le redémarrage le gardent.
    func updateTimerLine(noteID: Int64?, mode: TimerSession.Mode, seconds: TimeInterval) {
        guard let noteID, let note = (notes + archivedNotes).first(where: { $0.id == noteID }) else { return }
        let content = Self.contentWithTimerLine(note.content, mode: mode, seconds: Int(seconds.rounded()))
        guard content != note.content else { return }
        var updated = note
        updated.content = content
        edit(updated)
    }

    static func timerLine(mode: TimerSession.Mode, seconds: Int) -> String {
        mode == .stopwatch ? mode.rawValue : "\(mode.rawValue) \(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// Remplace la ligne de réglage (première ligne qui commence par un mode),
    /// ou l'ajoute sous l'en-tête ; le reste de la note n'est pas touché.
    static func contentWithTimerLine(_ content: String, mode: TimerSession.Mode, seconds: Int) -> String {
        var lines = content.components(separatedBy: "\n")
        let line = timerLine(mode: mode, seconds: seconds)
        let modeWords = ["countdown", "stopwatch", "pomodoro", "minuteur", "chrono"]
        if let index = lines.firstIndex(where: { candidate in
            let first = candidate.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").first.map(String.init) ?? ""
            return modeWords.contains(first)
        }) {
            lines[index] = line
        } else {
            let headerIndex = lines.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("timer") } == true ? 1 : 0
            lines.insert(line, at: min(headerIndex, lines.count))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Privé

    private func reloadNotes(selecting selectedID: Int64? = nil) {
        let allNotes = Note.fetchAll()
        notes = allNotes.filter { !$0.archived }
        archivedNotes = allNotes.filter { $0.archived }

        if notes.isEmpty {
            let created = Note.create(Note(position: 0))
            notes = [created]
            currentIndex = 0
            return
        }

        if let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }) {
            currentIndex = index
            return
        }
        currentIndex = min(max(currentIndex, 0), notes.count - 1)
    }

    private var legacyArchivedNoteIDs: Set<Int64> {
        guard let data = legacyArchivedNoteIDsStorage.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else { return [] }
        return Set(ids)
    }

    private func migrateLegacyArchiveIDsIfNeeded() {
        guard !archivedIDsMigratedToDatabase else { return }
        let archivedIDs = legacyArchivedNoteIDs
        guard !archivedIDs.isEmpty else {
            archivedIDsMigratedToDatabase = true
            return
        }
        for var note in Note.fetchAllIncludingDeleted() where archivedIDs.contains(note.id ?? -1) && !note.archived {
            note.archived = true
            Note.update(note)
        }
        legacyArchivedNoteIDsStorage = "[]"
        archivedIDsMigratedToDatabase = true
    }

    private func repairListNotesIfNeeded() {
        let selectedID = currentNote?.id
        var changed = false
        for note in notes + archivedNotes where note.keyword == "list" {
            let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: false)
            guard normalized != note.content else { continue }
            var updated = note
            updated.content = normalized
            updated.detectKeyword()
            Note.update(updated)
            changed = true
        }
        if changed { reloadNotes(selecting: selectedID) }
    }

    private func adjacentNoteID(forDeletedNoteID noteID: Int64?) -> Int64? {
        guard let noteID, let deletedIndex = notes.firstIndex(where: { $0.id == noteID }) else {
            return currentNote?.id
        }
        if deletedIndex + 1 < notes.count { return notes[deletedIndex + 1].id }
        if deletedIndex - 1 >= 0 { return notes[deletedIndex - 1].id }
        return nil
    }

    private func deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: Bool) -> Bool {
        guard let current = currentNote,
              current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let preferredID = preferPrevious ? notes[safe: currentIndex - 1]?.id : notes[safe: currentIndex + 1]?.id
        let fallbackID = preferPrevious ? notes[safe: currentIndex + 1]?.id : notes[safe: currentIndex - 1]?.id

        if let id = current.id {
            pendingSaveTasks[id]?.cancel()
            pendingNotes[id] = nil
        }
        Note.delete(current)
        TimerRegistry.shared.discard(noteUUID: current.uuid)
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: preferredID ?? fallbackID)
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
