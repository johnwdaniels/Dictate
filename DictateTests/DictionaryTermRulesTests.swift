import XCTest
@testable import Dictate

final class DictionaryTermRulesTests: XCTestCase {
    func testNamesTheDisallowedCharacter() {
        XCTAssertEqual(DictionaryTermRules.issue(for: "AT&T", existing: [], count: 0), "& isn't allowed.")
        XCTAssertEqual(DictionaryTermRules.issue(for: "user_name", existing: [], count: 0), "_ isn't allowed.")
        XCTAssertEqual(DictionaryTermRules.issue(for: "say \"hi\"", existing: [], count: 0), "\" isn't allowed.")
    }

    func testAllowsLettersDigitsSpacesAndListedPunctuation() {
        XCTAssertNil(DictionaryTermRules.issue(for: "東京", existing: [], count: 0))
        XCTAssertNil(DictionaryTermRules.issue(for: "O'Brien", existing: [], count: 0))
        XCTAssertNil(DictionaryTermRules.issue(for: "well-known", existing: [], count: 0))
        XCTAssertNil(DictionaryTermRules.issue(for: "3.14", existing: [], count: 0))
        XCTAssertTrue(DictionaryTermRules.canAdd("Dr. Smith (CEO)", existing: [], count: 0))
    }

    func testRejectsACaseInsensitiveDuplicateAndTheHundredTermCap() {
        XCTAssertEqual(
            DictionaryTermRules.issue(for: "tokyo", existing: ["Tokyo"], count: 1),
            "That term is already in the dictionary."
        )
        XCTAssertEqual(
            DictionaryTermRules.issue(for: "one more", existing: [], count: DictionaryTermRules.maximum),
            "The dictionary already has 100 terms."
        )
        XCTAssertFalse(DictionaryTermRules.canAdd("one more", existing: [], count: 100))
    }

    func testCleaningRewritesCurlyQuotesAndUnderscores() {
        XCTAssertEqual(DictionaryTermRules.cleaned("user_name"), "user name")
        XCTAssertEqual(DictionaryTermRules.cleaned("“Inworld”"), "'Inworld'")
        XCTAssertEqual(DictionaryTermRules.cleaned("‘hello’"), "'hello'")
        XCTAssertEqual(DictionaryTermRules.cleanTitle(for: "user_name"), "Replace _ with a space")
        XCTAssertEqual(DictionaryTermRules.cleanTitle(for: "“ok”"), "Replace “ ” with '")
        XCTAssertNil(DictionaryTermRules.cleanTitle(for: "Tokyo"))
    }

    func testImportSkipsBadCharactersDuplicatesAndStopsAtTheCap() {
        let plan = DictionaryTermRules.planImport(
            text: "AT&T\nuser_name\nTokyo\ntokyo\n\n  \n",
            existing: []
        )

        XCTAssertEqual(plan.accepted, ["Tokyo"])
        XCTAssertEqual(plan.skipped, [
            "Line 1: & isn't allowed.",
            "Line 2: _ isn't allowed.",
            "Line 4: tokyo is already in the dictionary.",
        ])

        let existing = (1...100).map { "term \($0)" }
        let full = DictionaryTermRules.planImport(text: "another term", existing: existing)
        XCTAssertTrue(full.accepted.isEmpty)
        XCTAssertEqual(full.skipped, ["Line 1: the dictionary already has 100 terms."])
    }
}
