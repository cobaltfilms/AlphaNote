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
        // "100 + 15%" → 115 (15% of 100)
        let result = evaluator.evaluate("100 + 15%")
        XCTAssertNotNil(result)
        if let result {
            XCTAssertEqual(result, 115.0, accuracy: 0.01)
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
}