import XCTest
@testable import AlphaNote

final class AlphaNoteTests: XCTestCase {

    // MARK: - MathEvaluator

    let evaluator = MathEvaluator()

    func testBasicArithmetic() {
        XCTAssertEqual(evaluator.evaluate("2 + 3"), 5.0)
        XCTAssertEqual(evaluator.evaluate("10 - 4"), 6.0)
        XCTAssertEqual(evaluator.evaluate("3 * 7"), 21.0)
        XCTAssertEqual(evaluator.evaluate("20 / 4"), 5.0)
    }

    func testOrderOfOperations() {
        XCTAssertEqual(evaluator.evaluate("2 + 3 * 4"), 14.0)
        XCTAssertEqual(evaluator.evaluate("(2 + 3) * 4"), 20.0)
    }

    func testExponentiation() {
        XCTAssertEqual(evaluator.evaluate("2 ^ 10"), 1024.0)
        XCTAssertEqual(evaluator.evaluate("3 ^ 3"), 27.0)
    }

    func testNegativeNumbers() {
        XCTAssertEqual(evaluator.evaluate("-5 + 10"), 5.0)
        XCTAssertEqual(evaluator.evaluate("10 * -3"), -30.0)
    }

    func testColloquialPercent() {
        XCTAssertEqual(evaluator.evaluate("50% of 200"), 100.0)
        XCTAssertEqual(evaluator.evaluate("25% of 80"), 20.0)
    }

    func testPercentAddition() {
        // "100 + 15%" → 100 + 0.15 = 100.15 (literal percent)
        // TODO: colloquial percent addition (15% of 100 → 115) for future version
        let result = evaluator.evaluate("100 + 15%")
        XCTAssertNotNil(result)
        if let result {
            XCTAssertEqual(result, 100.15, accuracy: 0.01)
        }
    }

    func testDecimalArithmetic() {
        XCTAssertEqual(evaluator.evaluate("0.5 * 10"), 5.0)
        XCTAssertEqual(evaluator.evaluate("1.5 + 2.5"), 4.0)
    }

    func testComplexExpressions() {
        XCTAssertEqual(evaluator.evaluate("2 * (3 + 4) ^ 2"), 98.0)
        XCTAssertEqual(evaluator.evaluate("100 - 20% of 50"), 90.0)
    }

    func testAlternateOperatorForms() {
        XCTAssertEqual(evaluator.evaluate("2 x 3"), 6.0)
        XCTAssertEqual(evaluator.evaluate("8 ÷ 2"), 4.0)
        XCTAssertEqual(evaluator.evaluate("2 ** 3"), 8.0)
    }

    // MARK: - Converter

    let converter = Converter()

    func testDistanceConversion() {
        let result = converter.convert("12km in miles")
        XCTAssertNotNil(result)
        if let result {
            XCTAssertTrue(result.contains("mi") || result.contains("7.45"), "Got: \(result)")
        }
    }

    func testTemperatureConversion() {
        let celsius = converter.convert("72f in c")
        XCTAssertNotNil(celsius)

        let fahrenheit = converter.convert("0c in f")
        XCTAssertNotNil(fahrenheit)
        if let fahrenheit {
            XCTAssertTrue(fahrenheit.contains("32"), "Got: \(fahrenheit)")
        }
    }

    func testMassConversion() {
        let result = converter.convert("1kg in lb")
        XCTAssertNotNil(result)
        if let result {
            XCTAssertTrue(result.contains("2.2"), "Got: \(result)")
        }
    }

    // MARK: - Sync merge

    func testSyncConflictChoosesMostRecentUpdate() {
        let older = CloudNoteDTO(
            note: Note(
                uuid: "11111111-1111-1111-1111-111111111111",
                content: "old",
                updatedAt: Date(timeIntervalSince1970: 100),
                lastModifiedByDeviceId: "device-a"
            )
        )
        let newer = CloudNoteDTO(
            note: Note(
                uuid: "11111111-1111-1111-1111-111111111111",
                content: "new",
                updatedAt: Date(timeIntervalSince1970: 200),
                lastModifiedByDeviceId: "device-b"
            )
        )

        let winner = SyncEngine.resolveConflict(older, newer)
        XCTAssertEqual(winner.content, "new")
    }

    func testSyncConflictTieBreaksByDeviceID() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let lhs = CloudNoteDTO(
            note: Note(
                uuid: "22222222-2222-2222-2222-222222222222",
                content: "from-a",
                updatedAt: sameDate,
                lastModifiedByDeviceId: "aaa-device"
            )
        )
        let rhs = CloudNoteDTO(
            note: Note(
                uuid: "22222222-2222-2222-2222-222222222222",
                content: "from-z",
                updatedAt: sameDate,
                lastModifiedByDeviceId: "zzz-device"
            )
        )

        let winner = SyncEngine.resolveConflict(lhs, rhs)
        XCTAssertEqual(winner.content, "from-a")
    }

    func testSyncConflictDeletedWinsWhenTimestampEqual() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let active = CloudNoteDTO(
            note: Note(
                uuid: "33333333-3333-3333-3333-333333333333",
                content: "active",
                isDeleted: false,
                updatedAt: sameDate,
                lastModifiedByDeviceId: "same-device"
            )
        )
        let deleted = CloudNoteDTO(
            note: Note(
                uuid: "33333333-3333-3333-3333-333333333333",
                content: "active",
                isDeleted: true,
                deletedAt: sameDate,
                updatedAt: sameDate,
                lastModifiedByDeviceId: "same-device"
            )
        )

        let winner = SyncEngine.resolveConflict(active, deleted)
        XCTAssertTrue(winner.isDeleted)
    }

    // MARK: - AI intents

    func testMathIntentDetectedFromExpression() {
        XCTAssertTrue(AIIntentDetector.isMathRequest("12 * 8", noteKeyword: nil))
    }

    func testMathIntentDetectedFromReductionRequest() {
        XCTAssertTrue(AIIntentDetector.isMathRequest("calcule le pourcentage de réduction", noteKeyword: nil))
    }

    func testMathIntentDetectedFromMathNoteKeyword() {
        XCTAssertTrue(AIIntentDetector.isMathRequest("n'importe quoi", noteKeyword: "math"))
    }

    func testMathIntentDetectedFromNoisyPricingSentence() {
        XCTAssertTrue(AIIntentDetector.isMathRequest("un type à 900 chevaux, il les vend à 580€ pièce", noteKeyword: nil))
    }

    func testListIntentDetectedFromIngredientsWithTypos() {
        XCTAssertTrue(AIIntentDetector.isListRequest("fais moi une list: ognion, courgette, tomate", noteKeyword: nil))
    }

    func testIntentClassifierPrefersMathWhenApplicable() {
        let intent = AIIntentDetector.classifyIntent("pourcentage reduction prix base 120 final 90", noteKeyword: nil)
        if case .math = intent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected math intent")
        }
    }

    func testIntentClassifierPrefersWebResearchForWebQuery() {
        let intent = AIIntentDetector.classifyIntent(
            "liste moi les modèles les plus performants cette semaine selon le web",
            noteKeyword: nil
        )
        if case .webResearch = intent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected webResearch intent")
        }
    }

    func testIntentClassifierPrefersWebResearchOverListForMixedQuery() {
        let intent = AIIntentDetector.classifyIntent(
            "liste moi le matériel nécessaire pour construire un NAS en 2026 selon le web",
            noteKeyword: nil
        )
        if case .webResearch = intent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected webResearch intent for mixed list+web query")
        }
    }

    func testRecipeURLListRequestIsWebResearchWhenNotInMathNote() {
        let intent = AIIntentDetector.classifyIntent(
            "liste moi les ingrédients nécessaires à cette recette en détail : https://www.elle.fr/Elle-a-Table/Recettes-de-cuisine/Porc-aux-piments-et-galettes-2068190",
            noteKeyword: nil
        )
        if case .webResearch = intent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected webResearch intent for recipe URL list request")
        }
    }

    func testRecipeURLListRequestStaysMathInMathNote() {
        let intent = AIIntentDetector.classifyIntent(
            "liste moi les ingrédients nécessaires à cette recette en détail : https://www.elle.fr/Elle-a-Table/Recettes-de-cuisine/Porc-aux-piments-et-galettes-2068190",
            noteKeyword: "math"
        )
        if case .math = intent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected math intent when current note is math")
        }
        XCTAssertFalse(
            AIIntentDetector.isMathRequest(
                "liste moi les ingrédients nécessaires à cette recette en détail : https://www.elle.fr/Elle-a-Table/Recettes-de-cuisine/Porc-aux-piments-et-galettes-2068190",
                noteKeyword: nil
            )
        )
    }

    func testURLDetectorNormalizesMalformedScheme() {
        let urls = URLDetector.extractURLs(from: "recette: htrp://example.com/page")
        XCTAssertTrue(urls.contains(where: { $0.absoluteString == "https://example.com/page" }))
    }

    func testURLDetectorSupportsWWWWithoutScheme() {
        let urls = URLDetector.extractURLs(from: "voir www.example.com/recette")
        XCTAssertTrue(urls.contains(where: { $0.absoluteString == "https://www.example.com/recette" }))
    }

    func testURLDetectorKeepsHTTPSURLInsideSentence() {
        let text = "liste ingrédients: https://www.elle.fr/Elle-a-Table/Recettes-de-cuisine/Porc-aux-piments-et-galettes-2068190 en détail"
        let urls = URLDetector.extractURLs(from: text)
        XCTAssertTrue(urls.contains(where: { $0.absoluteString.contains("elle.fr/Elle-a-Table/Recettes-de-cuisine/Porc-aux-piments-et-galettes-2068190") }))
    }

    func testSemanticParserSalvagesJSONWhenPrefixedByCommentary() throws {
        let raw = """
        Looking at the provided notes, here's the structured answer:
        {
          "answer": "Liste prête.",
          "operation": {
            "type": "list",
            "content": "- riz\\n- poulet\\n- gingembre",
            "title": "Courses"
          },
          "sources": ["url:https%3A%2F%2Fexample.com%2Frecipe"]
        }
        """

        let result = try AIResponseParser.parse(raw, for: .semanticAnswer)
        XCTAssertEqual(result.metadata["format"], "json_semantic")
        XCTAssertEqual(result.metadata["operation_type"], "list")
        XCTAssertEqual(result.metadata["operation_title"], "Courses")
        XCTAssertEqual(result.metadata["operation_content"], "- riz\n- poulet\n- gingembre")
    }
}
