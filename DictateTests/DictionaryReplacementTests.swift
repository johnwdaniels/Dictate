import XCTest
@testable import Dictate

final class DictionaryReplacementTests: XCTestCase {
    func testReplacesCaseInsensitivelyWithoutTouchingLongerWords() {
        let result = DictionaryReplacements.apply(
            [("teh", "the"), ("inworld", "Inworld")],
            to: "Teh Tehran inworld"
        )

        XCTAssertEqual(result, "the Tehran Inworld")
    }

    func testKeepsADollarReplacementLiteral() {
        let result = DictionaryReplacements.apply([("a", "$1")], to: "a")

        XCTAssertEqual(result, "$1")
    }

    func testLongerFindWinsOverAShorterOne() {
        let result = DictionaryReplacements.apply(
            [("john", "J"), ("john daniels", "JD")],
            to: "John Daniels and john"
        )

        XCTAssertEqual(result, "JD and J")
    }

    func testEmptyFindIsIgnoredAndAnEmptyReplacementDeletesTheMatch() {
        XCTAssertNil(DictionaryReplacements.issue(for: "   ", existing: []))
        XCTAssertFalse(DictionaryReplacements.canAdd(find: " ", existing: []))
        XCTAssertEqual(
            DictionaryReplacements.issue(for: "Teh", existing: ["teh"]),
            "That replacement is already in the list."
        )
        XCTAssertEqual(
            DictionaryReplacements.apply([("um", "")], to: "say um now"),
            "say  now"
        )
    }
}
