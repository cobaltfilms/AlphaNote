import XCTest
@testable import AlphaNote

/// Demandes de liste appliquées sans IA : mêmes règles qu'Android
/// (NoteViewModel.listItems / listTitle / ensureListHeader).
final class ListRequestTests: XCTestCase {
    func testDestinationIsNotAnItem() {
        XCTAssertEqual(AIStore.listItems(from: "ajoute du café, du beurre et des pommes à mes courses"),
                       ["du café", "du beurre", "des pommes"])
        XCTAssertEqual(AIStore.listItems(from: "ajoute de l'huile d'olive dans la liste"), ["de l'huile d'olive"])
    }

    func testPlainEnumerationIsUntouched() {
        XCTAssertEqual(AIStore.listItems(from: "courses : tomates, pâtes, huile"), ["tomates", "pâtes", "huile"])
    }

    func testTitleIsGeneric() {
        XCTAssertEqual(AIStore.listTitle(from: "ajoute du café à mes courses"), "Courses")
        XCTAssertEqual(AIStore.listTitle(from: "liste des tâches de demain"), "Tâches")
        XCTAssertEqual(AIStore.listTitle(from: "valise : maillot, crème"), "Liste")
    }

    func testNewItemsAreAppendedToExistingList() {
        var note = Note()
        note.content = "list: Courses\n* pain\n* lait /x\n"
        XCTAssertEqual(AIStore.ensureListHeader(note), "list: Courses\n* pain\n* lait /x")
        note.content = "pain"
        XCTAssertEqual(AIStore.ensureListHeader(note), "list\npain")
    }
}
