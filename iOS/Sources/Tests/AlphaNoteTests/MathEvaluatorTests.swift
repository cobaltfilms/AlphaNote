import XCTest
@testable import AlphaNote

final class MathEvaluatorTests: XCTestCase {
    let evaluator = MathEvaluator()

    func testBasicAddition() {
        XCTAssertEqual(evaluator.evaluate("2 + 3"), 5.0)
    }

    func testSubtraction() {
        XCTAssertEqual(evaluator.evaluate("10 - 4"), 6.0)
    }

    func testMultiplication() {
        XCTAssertEqual(evaluator.evaluate("6 * 7"), 42.0)
    }

    func testDivision() {
        XCTAssertEqual(evaluator.evaluate("15 / 3"), 5.0)
    }

    func testPower() {
        XCTAssertEqual(evaluator.evaluate("2 ^ 8"), 256.0)
    }

    func testParentheses() {
        XCTAssertEqual(evaluator.evaluate("(2 + 3) * 4"), 20.0)
    }

    func testPercent() {
        XCTAssertEqual(evaluator.evaluate("200 + 10%"), 220.0)
    }

    func testSqrt() {
        XCTAssertEqual(evaluator.evaluate("√16"), 4.0)
    }

    func testComplexExpression() {
        XCTAssertEqual(evaluator.evaluate("3 * (4 + 2) / 3"), 6.0)
    }

    func testInvalidExpression() {
        XCTAssertNil(evaluator.evaluate("abc"))
    }
}
