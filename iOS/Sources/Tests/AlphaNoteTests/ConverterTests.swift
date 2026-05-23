import XCTest
@testable import AlphaNote

final class ConverterTests: XCTestCase {
    let converter = Converter()

    func testKmToMiles() {
        let result = converter.convert("10 km to mi")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("6.21") ?? false)
    }

    func testKgToLbs() {
        let result = converter.convert("72 kg to lbs")
        XCTAssertNotNil(result)
    }

    func testCelsiusToFahrenheit() {
        let result = converter.convert("100 °C to °F")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("212") ?? false)
    }

    func testInvalidConversion() {
        XCTAssertNil(converter.convert("abc to xyz"))
    }
}
