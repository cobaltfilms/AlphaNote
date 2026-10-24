import XCTest
@testable import AlphaNote

/// Évaluateur arithmétique, document math, conversions et devises (sans réseau).
final class EvaluationTests: XCTestCase {
    private let evaluator = MathEvaluator()

    // MARK: - MathEvaluator : fonctions et tolérance

    func testFunctionsAndConstants() {
        XCTAssertEqual(evaluator.evaluate("sqrt(16)"), 4)
        XCTAssertEqual(evaluator.evaluate("abs(-3)"), 3)
        XCTAssertEqual(evaluator.evaluate("round(2.6)"), 3)
        XCTAssertEqual(evaluator.evaluate("floor(2.6) + ceil(2.1)"), 5)
        XCTAssertEqual(evaluator.evaluate("log(1000)")!, 3, accuracy: 1e-9)
        XCTAssertEqual(evaluator.evaluate("ln(1)"), 0)
        XCTAssertEqual(evaluator.evaluate("max(1, 7, 3)"), 7)
        XCTAssertEqual(evaluator.evaluate("min(4; 2)"), 2)
        XCTAssertEqual(evaluator.evaluate("2 pi")!, 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(evaluator.evaluate("π")!, Double.pi, accuracy: 1e-9)
    }

    func testFactorialAndImplicitMultiplication() {
        XCTAssertEqual(evaluator.evaluate("5!"), 120)
        XCTAssertEqual(evaluator.evaluate("3! + 1"), 7)
        XCTAssertEqual(evaluator.evaluate("2(3 + 4)"), 14)
        XCTAssertNil(evaluator.evaluate("(-1)!"))
        XCTAssertNil(evaluator.evaluate("2.5!"))
    }

    func testUnknownWordsAreIgnoredButUnknownFunctionsFail() {
        XCTAssertEqual(evaluator.evaluate("5 pommes + 3 pommes"), 8)
        XCTAssertEqual(evaluator.evaluate("10 kg + 5"), 15)
        XCTAssertNil(evaluator.evaluate("foo(3)"))
        XCTAssertNil(evaluator.evaluate("sqrt(-1)"))
        XCTAssertNil(evaluator.evaluate(""))
        XCTAssertNil(evaluator.evaluate("+"))
    }

    func testDecimalCommaAndUnicodeOperators() {
        XCTAssertEqual(evaluator.evaluate("1,5 + 1,5"), 3)
        XCTAssertEqual(evaluator.evaluate("10 − 4"), 6)
        XCTAssertEqual(evaluator.evaluate("3 × 3"), 9)
        XCTAssertEqual(evaluator.evaluate("2 ^ 3 ^ 2"), 512) // associatif à droite
        XCTAssertEqual(evaluator.evaluate("-(2 + 3)"), -5)
        XCTAssertEqual(evaluator.evaluate("--2"), 2)
    }

    func testDivisionByZeroIsRejected() {
        XCTAssertNil(evaluator.evaluate("1 / 0"))
    }

    // MARK: - MathDocumentEvaluator

    func testDocumentVariablesAndInlineResults() {
        let document = MathDocumentEvaluator(converter: Converter(rateService: CurrencyRateService(session: .shared, persists: false)))
        let content = """
        math: Budget
        loyer: 900
        courses: 350
        loyer + courses =
        total: loyer + courses =
        // commentaire
        total * 12 =
        """
        let output = document.transformed(content: content)
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "math: Budget")
        XCTAssertEqual(lines[3], "loyer + courses = 1250")
        XCTAssertEqual(lines[4], "total: loyer + courses = 1250")
        XCTAssertEqual(lines[5], "// commentaire")
        XCTAssertEqual(lines[6], "total * 12 = 15000")
    }

    func testDocumentClearsStaleResultAndKeepsPercentVariables() {
        let document = MathDocumentEvaluator()
        let content = """
        math
        prix: 200
        remise: 15%
        prix - remise =
        2 + =
        """
        let lines = document.transformed(content: content).components(separatedBy: "\n")
        XCTAssertEqual(lines[3], "prix - remise = 170")
        XCTAssertEqual(lines[4], "2 + =", "une expression inévaluable vide sa partie droite")
    }

    func testDocumentUnitsAndMixedUnits() {
        let document = MathDocumentEvaluator()
        let content = """
        math
        10 kg + 500 g =
        3 km + 2 l =
        12 km to mi =
        """
        let lines = document.transformed(content: content).components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "10 kg + 500 g = 10.5 kg")
        XCTAssertTrue(lines[2].contains("⚠︎"), "unités incompatibles : \(lines[2])")
        XCTAssertTrue(lines[3].hasPrefix("12 km to mi = 7.45"), lines[3])
    }

    func testVariableAssignmentParsing() {
        XCTAssertNotNil(MathDocumentEvaluator.parseVariableAssignment(from: "prix ht: 100"))
        XCTAssertNil(MathDocumentEvaluator.parseVariableAssignment(from: "math: titre"))
        XCTAssertNil(MathDocumentEvaluator.parseVariableAssignment(from: "10:30 + 2"))
        let withResult = MathDocumentEvaluator.parseVariableAssignment(from: "total: 2 + 2 =")
        XCTAssertEqual(withResult?.expression, "2 + 2")
        XCTAssertEqual(withResult?.showsResult, true)
    }

    // MARK: - Devises (cache, sans réseau)

    func testCurrencyConversionUsesCachedRateAndNeverBlocks() {
        let service = CurrencyRateService(session: .shared, persists: false)
        service.fetcher = { _ in throw URLError(.notConnectedToInternet) }
        service.seed(base: "USD", rates: ["EUR": 0.5, "JPY": 150])
        let converter = Converter(rateService: service)

        XCTAssertEqual(converter.convert("100 USD to EUR"), "50 EUR")
        XCTAssertEqual(converter.convert("$10 to JPY"), "1500 JPY")

        let start = Date()
        XCTAssertNil(converter.convert("10 CHF to EUR"), "taux absent → nil, pas d'attente réseau")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testCurrencyParsingOfProviders() async {
        let service = CurrencyRateService(session: .shared, persists: false)
        service.fetcher = { url in
            if url.host?.contains("frankfurter") == true {
                return Data(#"{"amount":1,"base":"USD","rates":{"EUR":0.9}}"#.utf8)
            }
            throw URLError(.badServerResponse)
        }
        let snapshot = await service.refresh(base: "USD")
        XCTAssertEqual(snapshot?.rates["EUR"], 0.9)
        XCTAssertEqual(service.rate(from: "usd", to: "eur"), 0.9)
    }

    func testDocumentShowsPendingMarkerWhileRatesLoad() {
        let service = CurrencyRateService(session: .shared, persists: false)
        service.fetcher = { _ in throw URLError(.notConnectedToInternet) }
        let document = MathDocumentEvaluator(converter: Converter(rateService: service))
        let lines = document.transformed(content: "math\n10 CHF to NOK =").components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "10 CHF to NOK = …")
    }

    func testRelativePercentAfterPlusOrMinus() {
        let evaluator = MathEvaluator()
        XCTAssertEqual(evaluator.evaluate("100 - 20%"), 80)
        XCTAssertEqual(evaluator.evaluate("200 + 10%"), 220)
        XCTAssertEqual(evaluator.evaluate("50% of 200"), 100)
        XCTAssertEqual(evaluator.evaluate("20% + 5"), 5.2)
    }
}
