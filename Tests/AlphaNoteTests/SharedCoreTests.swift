import XCTest
@testable import AlphaNote

/// Logique partagée macOS / iOS : résultats math en ligne, règles de l'éditeur,
/// images jointes (même format qu'Android).
final class SharedCoreTests: XCTestCase {

    // MARK: - MathInlineApplier

    func testInlineResultReplacesOnlyTheTail() {
        let document = MathDocumentEvaluator()
        let content = "math\na: 5\na * 2 ="
        let edits = MathInlineApplier.edits(for: content, caret: nil, evaluator: document)
        let result = MathInlineApplier.apply(edits, to: content)
        XCTAssertEqual(result, "math\na: 5\na * 2 = 10")
    }

    func testInlineResultWaitsWhileCaretIsInsideTheResult() {
        let document = MathDocumentEvaluator()
        let content = "math\n2 + 2 = 9"
        let caret = (content as NSString).length // au bout de « 9 »
        XCTAssertTrue(MathInlineApplier.edits(for: content, caret: caret, evaluator: document).isEmpty)
        XCTAssertFalse(MathInlineApplier.edits(for: content, caret: nil, evaluator: document).isEmpty)
    }

    func testCaretMovesWithEditsBeforeIt() {
        let edits = [MathInlineApplier.Edit(range: NSRange(location: 3, length: 0), replacement: " 10")]
        XCTAssertEqual(MathInlineApplier.adjustedCaret(10, after: edits), 13)
        XCTAssertEqual(MathInlineApplier.adjustedCaret(2, after: edits), 2)
    }

    // MARK: - EditorTextRules

    func testToggleListLineAddsAndRemovesTrigger() {
        XCTAssertEqual(EditorTextRules.toggledListLine("- pain", trigger: "/x"), "- pain /x")
        XCTAssertEqual(EditorTextRules.toggledListLine("- pain /x  ", trigger: "/x"), "- pain")
        XCTAssertEqual(EditorTextRules.toggledListLine("lait", trigger: ""), "lait /x")
    }

    func testBulletRules() {
        XCTAssertEqual(EditorTextRules.bulletMarker(in: "  - pain"), "  - ")
        XCTAssertNil(EditorTextRules.bulletMarker(in: "pain"))
        XCTAssertTrue(EditorTextRules.isEmptyBullet("- "))
        XCTAssertFalse(EditorTextRules.isEmptyBullet("- pain"))
    }

    func testModeDetection() {
        XCTAssertEqual(EditorTextRules.detectMode(in: "list: Courses\n- pain"), .list)
        XCTAssertEqual(EditorTextRules.detectMode(in: "math\n1+1="), .math)
        XCTAssertEqual(EditorTextRules.detectMode(in: "Bonjour"), .plain)
        XCTAssertTrue(EditorTextRules.isModeHeader("timer: Thé"))
    }

    // MARK: - NoteAttachments (mêmes cas qu'Android NoteAttachmentsTest)

    func testMarkdownRoundTripsThroughNames() {
        let content = "Recette\n" + NoteAttachments.markdown("a1b2.jpg") + "\nÉtapes"
        XCTAssertEqual(NoteAttachments.names(in: content), ["a1b2.jpg"])
    }

    func testNamesKeepOrderOfAppearance() {
        let content = "\(NoteAttachments.markdown("first.jpg"))\ntexte\n\(NoteAttachments.markdown("second.jpg"))"
        XCTAssertEqual(NoteAttachments.names(in: content), ["first.jpg", "second.jpg"])
    }

    func testOrdinaryMarkdownLinksAreNotImages() {
        XCTAssertEqual(NoteAttachments.names(in: "[lien](https://example.com/att:x.jpg)"), [])
    }

    func testShareTextDropsImageLinesOnly() {
        let content = "liste\n\(NoteAttachments.markdown("x.jpg"))\n- pain\n"
        XCTAssertEqual(NoteAttachments.textWithoutImages(content), "liste\n- pain")
    }

    func testNormalizedJPEGRejectsNonImages() {
        XCTAssertNil(NoteAttachments.normalizedJPEG(from: Data("pas une image".utf8)))
    }
}
