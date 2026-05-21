import Foundation
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var archivedNotes: [Note] = []
    @Published var currentIndex: Int = 0
    @AppStorage("archivedNoteIDs") private var legacyArchivedNoteIDsStorage: String = "[]"
    @AppStorage("archivedIDsMigratedToDatabase") private var archivedIDsMigratedToDatabase: Bool = false

    var currentNote: Note? {
        guard !notes.isEmpty, currentIndex >= 0, currentIndex < notes.count else {
            return nil
        }
        return notes[currentIndex]
    }

    func loadNotes() {
        migrateLegacyArchiveIDsIfNeeded()
        reloadNotes()
        repairListNotesIfNeeded()
    }

    func addNote() {
        let allPositions = (notes + archivedNotes).map(\.position)
        let position = (allPositions.max() ?? -1) + 1
        let created = Note.create(Note(position: position))
        guard let createdID = created.id else {
            reloadNotes()
            return
        }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
    }

    func selectNote(id: Int64) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
    }

    func isArchived(_ note: Note) -> Bool {
        note.archived
    }

    func archiveNote(_ note: Note) {
        var updated = note
        updated.archived = true
        updateNote(updated)
        let nextSelection = adjacentNoteID(forDeletedNoteID: note.id)
        reloadNotes(selecting: nextSelection)
    }

    func unarchiveNote(_ note: Note) {
        var updated = note
        updated.archived = false
        updateNote(updated)
        reloadNotes(selecting: note.id)
    }

    func duplicateNote(_ note: Note) {
        var duplicated = note
        duplicated.id = nil
        duplicated.uuid = UUID().uuidString.lowercased()
        duplicated.createdAt = Date()
        duplicated.updatedAt = Date()
        duplicated.archived = false
        duplicated.isDeleted = false
        duplicated.deletedAt = nil
        duplicated.lastSyncedAt = nil
        duplicated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
        let allPositions = (notes + archivedNotes).map(\.position)
        duplicated.position = (allPositions.max() ?? -1) + 1

        let created = Note.create(duplicated)
        guard let createdID = created.id else {
            reloadNotes()
            return
        }

        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
    }

    func renameNote(_ note: Note, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = note
        let lines = updated.content.components(separatedBy: .newlines)
        let firstLine = lines.first ?? ""
        let remaining = Array(lines.dropFirst())

        if ListModeFormatter.isListHeader(firstLine) {
            updated.content = remaining.isEmpty
                ? "list: \(trimmed)"
                : (["list: \(trimmed)"] + remaining).joined(separator: "\n")
        } else if lines.isEmpty {
            updated.content = trimmed
        } else {
            updated.content = ([trimmed] + remaining).joined(separator: "\n")
        }

        updated.detectKeyword()
        updateNote(updated)
    }

    func convertCurrentNoteToList() {
        guard var note = currentNote else { return }
        let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: true)
        guard normalized != note.content else { return }
        note.content = normalized
        note.detectKeyword()
        updateNote(note)
    }

    func updateNote(_ note: Note) {
        Note.update(note)
        var updated = note
        updated.detectKeyword()
        updated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = updated
        }
        if let index = archivedNotes.firstIndex(where: { $0.id == note.id }) {
            archivedNotes[index] = updated
        }
        SyncEngine.shared.notifyLocalChange()
    }

    func deleteNote(_ note: Note) {
        let nextSelection = adjacentNoteID(forDeletedNoteID: note.id)
        Note.delete(note)
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: nextSelection)
    }

    func deleteEmptyNotes() {
        let selectedID = currentNote?.id
        Note.deleteEmpty()
        reloadNotes(selecting: selectedID)
    }

    func navigateNext() {
        guard !notes.isEmpty else {
            addNote()
            return
        }

        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: false) {
            return
        }

        if currentIndex < notes.count - 1 {
            currentIndex += 1
        } else {
            addNote()
        }
    }

    func navigatePrevious() {
        guard !notes.isEmpty else {
            addNote()
            return
        }

        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: true) {
            return
        }

        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    func viewForNote(_ note: Note) -> AnyView {
        let noteBinding = binding(for: note)

        switch note.keyword {
        case "math":
            return AnyView(MathNoteView(note: noteBinding))
        case "list":
            return AnyView(ListNoteView(note: noteBinding))
        case "code":
            return AnyView(CodeNoteView(note: noteBinding))
        case "timer":
            return AnyView(TimerNoteView())
        default:
            return AnyView(PlainNoteView(note: noteBinding))
        }
    }

    private func binding(for note: Note) -> Binding<Note> {
        Binding(
            get: {
                guard let noteID = note.id,
                      let index = self.notes.firstIndex(where: { $0.id == noteID }) else {
                    return note
                }
                return self.notes[index]
            },
            set: { updatedNote in
                if let noteID = updatedNote.id,
                   let index = self.notes.firstIndex(where: { $0.id == noteID }) {
                    self.notes[index] = updatedNote
                } else if self.currentIndex >= 0 && self.currentIndex < self.notes.count {
                    self.notes[self.currentIndex] = updatedNote
                }

                self.updateNote(updatedNote)
            }
        )
    }

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

        if let selectedID,
           let index = notes.firstIndex(where: { $0.id == selectedID }) {
            currentIndex = index
            return
        }

        currentIndex = min(max(currentIndex, 0), notes.count - 1)
    }

    private var legacyArchivedNoteIDs: Set<Int64> {
        guard let data = legacyArchivedNoteIDsStorage.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    private func setLegacyArchivedNoteIDs(_ ids: Set<Int64>) {
        let sorted = ids.sorted()
        if let data = try? JSONEncoder().encode(sorted),
           let json = String(data: data, encoding: .utf8) {
            legacyArchivedNoteIDsStorage = json
        }
    }

    private func migrateLegacyArchiveIDsIfNeeded() {
        guard !archivedIDsMigratedToDatabase else { return }

        let archivedIDs = legacyArchivedNoteIDs
        guard !archivedIDs.isEmpty else {
            archivedIDsMigratedToDatabase = true
            return
        }

        let existing = Note.fetchAllIncludingDeleted()
        for var note in existing where archivedIDs.contains(note.id ?? -1) {
            if note.archived {
                continue
            }
            note.archived = true
            Note.update(note)
        }

        setLegacyArchivedNoteIDs([])
        archivedIDsMigratedToDatabase = true
    }

    private func repairListNotesIfNeeded() {
        let selectedID = currentNote?.id
        let candidates = notes + archivedNotes
        var changed = false

        for note in candidates where note.keyword == "list" {
            let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: false)
            guard normalized != note.content else { continue }

            var updated = note
            updated.content = normalized
            updated.detectKeyword()
            Note.update(updated)
            changed = true
        }

        if changed {
            reloadNotes(selecting: selectedID)
        }
    }

    private func adjacentNoteID(forDeletedNoteID noteID: Int64?) -> Int64? {
        guard let noteID,
              let deletedIndex = notes.firstIndex(where: { $0.id == noteID }) else {
            return currentNote?.id
        }

        if deletedIndex + 1 < notes.count {
            return notes[deletedIndex + 1].id
        }

        if deletedIndex - 1 >= 0 {
            return notes[deletedIndex - 1].id
        }

        return nil
    }

    private func deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: Bool) -> Bool {
        guard let current = currentNote else {
            return false
        }

        if !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        let preferredID = preferPrevious
            ? notes[safe: currentIndex - 1]?.id
            : notes[safe: currentIndex + 1]?.id
        let fallbackID = preferPrevious
            ? notes[safe: currentIndex + 1]?.id
            : notes[safe: currentIndex - 1]?.id

        Note.delete(current)
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: preferredID ?? fallbackID)
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
