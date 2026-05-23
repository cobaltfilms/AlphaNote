import Foundation
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentIndex: Int = 0
    @Published var isAIProcessing = false
    @Published var aiError: String?

    private let mathEvaluator = MathEvaluator()
    private let converter = Converter()

    var currentNote: Note? {
        guard !notes.isEmpty, currentIndex >= 0, currentIndex < notes.count else { return nil }
        return notes[currentIndex]
    }

    func loadNotes() {
        guard let db = DatabaseManager.shared.queue else { return }
        do {
            notes = try db.read { try Note.fetchAll($0, sql: "SELECT * FROM note WHERE archived = 0 AND isDeleted = 0 ORDER BY position DESC") }
        } catch {
            print("[AlphaNote iOS] loadNotes failed: \(error)")
        }
    }

    func addNote() {
        guard let db = DatabaseManager.shared.queue else { return }
        let allPositions = notes.map(\.position)
        let position = (allPositions.max() ?? -1) + 1
        var note = Note(position: position, createdAt: Date(), updatedAt: Date())
        do {
            try db.write { try note.insert($0) }
            loadNotes()
        } catch {
            print("[AlphaNote iOS] addNote failed: \(error)")
        }
    }

    func updateNoteContent(_ note: Note) {
        guard let db = DatabaseManager.shared.queue, let id = note.id else { return }
        var mutable = note
        mutable.updatedAt = Date()
        // Détecter le keyword
        let firstLine = note.content.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if Note.knownKeywords.contains(firstLine) {
            mutable.keyword = firstLine
        }
        do {
            try db.write { try mutable.update($0) }
        } catch {
            print("[AlphaNote iOS] update failed: \(error)")
        }
    }

    func deleteNote(_ note: Note) {
        guard let db = DatabaseManager.shared.queue, let id = note.id else { return }
        do {
            try db.write { try Note.deleteOne($0, key: id) }
            loadNotes()
        } catch {
            print("[AlphaNote iOS] delete failed: \(error)")
        }
    }

    func togglePin(_ note: Note) {
        guard let db = DatabaseManager.shared.queue, let id = note.id else { return }
        var mutable = note
        mutable.isPinned.toggle()
        do {
            try db.write { try mutable.update($0) }
            loadNotes()
        } catch {
            print("[AlphaNote iOS] togglePin failed: \(error)")
        }
    }

    func note(byID id: Int64) -> Note? {
        notes.first(where: { $0.id == id })
    }

    func selectNote(byUUID uuid: String) {
        guard let idx = notes.firstIndex(where: { $0.uuid == uuid }) else { return }
        currentIndex = idx
    }

    // MARK: - AI operations (simplifiées pour iOS)

    func cancelAIOperation() {
        isAIProcessing = false
        aiError = nil
    }

    func summarizeCurrentNote() async {
        isAIProcessing = true
        aiError = nil
        // TODO: brancher AIService
        isAIProcessing = false
    }

    func rewriteCurrentNote(style: RewriteStyle) async {
        isAIProcessing = true
        aiError = nil
        // TODO: brancher AIService
        isAIProcessing = false
    }

    func extractActionsCurrentNote() async {
        isAIProcessing = true
        aiError = nil
        // TODO: brancher AIService
        isAIProcessing = false
    }
}
