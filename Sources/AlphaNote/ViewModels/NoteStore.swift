import Foundation
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentIndex: Int = 0

    var currentNote: Note? {
        guard !notes.isEmpty, currentIndex >= 0, currentIndex < notes.count else {
            return nil
        }
        return notes[currentIndex]
    }

    func loadNotes() {
        reloadNotes()
    }

    func addNote() {
        let position = (notes.map(\.position).max() ?? -1) + 1
        let created = Note.create(Note(position: position))
        guard let createdID = created.id else {
            reloadNotes()
            return
        }
        reloadNotes(selecting: createdID)
    }

    func selectNote(id: Int64) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
    }

    func updateNote(_ note: Note) {
        Note.update(note)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updated = note
            updated.detectKeyword()
            notes[index] = updated
        }
    }

    func deleteNote(_ note: Note) {
        let nextSelection = adjacentNoteID(forDeletedNoteID: note.id)
        Note.delete(note)
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
        notes = Note.fetchAll()

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
