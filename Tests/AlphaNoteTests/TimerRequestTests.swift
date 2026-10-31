import XCTest
@testable import AlphaNote

/// « minuteur 5 minutes » depuis une note : la note vide devient le minuteur,
/// une note qui a du texte en garde un à part et le minuteur est sélectionné.
@MainActor
final class TimerRequestTests: XCTestCase {
    private var store: NoteStore!

    override func setUp() async throws {
        try DatabaseManager.shared.useInMemoryDatabaseForTesting()
        UserDefaults.standard.set(false, forKey: AISettingsKeys.enabled)
        store = NoteStore()
        store.loadNotes()
    }

    func testEmptyNoteBecomesTheTimer() async throws {
        let note = try XCTUnwrap(store.addNote())
        let before = Note.fetchAll().count
        await store.aiStore.routeQuestion("minuteur 5 minutes")
        XCTAssertEqual(Note.fetchAll().count, before, "pas de note en plus")
        XCTAssertEqual(store.currentNote?.id, note.id)
        XCTAssertEqual(store.currentNote?.keyword, "timer")
        XCTAssertEqual(store.currentNote?.content, "timer\ncountdown 5:00")
    }

    func testNoteWithTextKeepsItAndSelectsNewTimer() async throws {
        let note = try XCTUnwrap(store.addNote(content: "courses"))
        await store.aiStore.routeQuestion("minuteur 5 minutes")
        XCTAssertNotEqual(store.currentNote?.id, note.id)
        XCTAssertEqual(store.currentNote?.keyword, "timer")
        XCTAssertEqual(Note.fetchAll().first { $0.id == note.id }?.content, "courses")
    }
}
