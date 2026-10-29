import XCTest
@testable import Dictate

final class SmartSpacingTests: XCTestCase {
    func testAddsASpaceAfterTheEndOfTheLastDictation() {
        XCTAssertEqual(SmartSpacing.spaced("To maximize leverage.", after: "?"), " To maximize leverage.")
        XCTAssertEqual(SmartSpacing.spaced("and then", after: "d"), " and then")
    }

    func testLeavesTextAloneAtTheStartOrAfterASpace() {
        XCTAssertEqual(SmartSpacing.spaced("Hello", after: nil), "Hello")
        XCTAssertEqual(SmartSpacing.spaced("Hello", after: " "), "Hello")
        XCTAssertEqual(SmartSpacing.spaced("Hello", after: "\n"), "Hello")
    }

    func testNoSpaceBeforePunctuationOrAfterAnOpeningMark() {
        XCTAssertEqual(SmartSpacing.spaced(", and more", after: "s"), ", and more")
        XCTAssertEqual(SmartSpacing.spaced("?", after: "y"), "?")
        XCTAssertEqual(SmartSpacing.spaced("quoted", after: "“"), "quoted")
        XCTAssertEqual(SmartSpacing.spaced("aside", after: "("), "aside")
    }
}
