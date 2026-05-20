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
        notes = Note.fetchAll()
        if notes.isEmpty {
            addNote()
        }
        if currentIndex >= notes.count {
            currentIndex = max(0, notes.count - 1)
        }
    }

    func addNote() {
        let position = (notes.map(\.position).max() ?? -1) + 1
        var note = Note(position: position)
        Note.create(note)
        if let created = Note.fetchAll().last {
            note = created
        }
        notes.append(note)
        currentIndex = notes.count - 1
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
        Note.delete(note)
        notes.removeAll { $0.id == note.id }
        if currentIndex >= notes.count {
            currentIndex = max(0, notes.count - 1)
        }
        if notes.isEmpty {
            addNote()
        }
    }

    func deleteEmptyNotes() {
        Note.deleteEmpty()
        notes.removeAll { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if currentIndex >= notes.count {
            currentIndex = max(0, notes.count - 1)
        }
        if notes.isEmpty {
            addNote()
        }
    }

    func navigateNext() {
        if currentIndex < notes.count - 1 {
            currentIndex += 1
        } else {
            let currentNote = notes[currentIndex]
            if currentNote.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deleteNote(currentNote)
            } else {
                addNote()
            }
        }
    }

    func navigatePrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            let currentNote = notes[currentIndex]
            if currentNote.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deleteNote(currentNote)
            }
        }
    }

    func viewForNote(_ note: Note) -> AnyView {
        switch note.keyword {
        case "math":
            return AnyView(MathNoteView(note: Binding(
                get: { note },
                set: { self.updateNote($0) }
            )))
        case "list":
            return AnyView(ListNoteView(note: Binding(
                get: { note },
                set: { self.updateNote($0) }
            )))
        case "code":
            return AnyView(CodeNoteView(note: Binding(
                get: { note },
                set: { self.updateNote($0) }
            )))
        case "timer":
            return AnyView(TimerNoteView())
        default:
            return AnyView(PlainNoteView(note: Binding(
                get: { note },
                set: { self.updateNote($0) }
            )))
        }
    }
}