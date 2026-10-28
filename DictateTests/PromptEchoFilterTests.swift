import XCTest
@testable import Dictate

final class PromptEchoFilterTests: XCTestCase {
    private let terms = ["Inworld", "GTM Sage", "Ryder", "Superhuman", "Adele"]

    private func filter(_ segment: String, first: Bool = false) -> String {
        PromptEchoFilter.filter(segment, terms: terms, isFirstSegment: first)
    }

    func testASegmentMadeOnlyOfTermsIsDropped() {
        XCTAssertEqual(filter("Inworld, GTM Sage, Ryder, Superhuman, Adele."), "")
        XCTAssertEqual(filter("Inworld Ryder", first: true), "")
        XCTAssertEqual(filter("Superhuman.", first: false), "")
    }

    func testALoneTermSpokenAsTheWholeDictationStays() {
        XCTAssertEqual(filter("Inworld.", first: true), "Inworld.")
    }

    func testSpeechThatMentionsTermsStays() {
        XCTAssertEqual(filter("Send it to Ryder in Superhuman.", first: true), "Send it to Ryder in Superhuman.")
        XCTAssertEqual(filter("Ryder and Adele are on the call."), "Ryder and Adele are on the call.")
        // Two names in the saved order are a real list, not the prompt.
        XCTAssertEqual(filter("Loop in Ryder, Superhuman."), "Loop in Ryder, Superhuman.")
    }

    func testAnOrderedRunAtTheEndIsTrimmed() {
        XCTAssertEqual(filter("We should ship it today. Inworld, GTM Sage, Ryder.", first: true), "We should ship it today.")
        XCTAssertEqual(filter("Sounds good Ryder Superhuman Adele", first: true), "Sounds good")
    }

    func testAnOrderedRunAtTheStartIsTrimmed() {
        XCTAssertEqual(filter("Inworld, GTM Sage, Ryder. Let's meet Tuesday.", first: true), "Let's meet Tuesday.")
    }

    func testOutOfOrderNamesInSpeechStay() {
        XCTAssertEqual(filter("Invite Adele, Ryder, Inworld folks.", first: true), "Invite Adele, Ryder, Inworld folks.")
    }

    func testMatchingIgnoresCaseAndPunctuation() {
        XCTAssertEqual(filter("inworld... gtm sage? RYDER!"), "")
    }

    func testNoTermsMeansNoChange() {
        XCTAssertEqual(PromptEchoFilter.filter("Inworld Ryder", terms: [], isFirstSegment: false), "Inworld Ryder")
    }
}
