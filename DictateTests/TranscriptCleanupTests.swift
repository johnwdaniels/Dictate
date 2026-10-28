import XCTest
@testable import Dictate

final class TranscriptCleanupTests: XCTestCase {
    private func fillers(_ text: String) -> String { TranscriptCleanup.removingFillers(text) }
    private func numbers(_ text: String) -> String { TranscriptCleanup.formattingNumbers(text) }

    func testFillerSoundsAreRemoved() {
        XCTAssertEqual(fillers("So, um, we ship Friday."), "So, we ship Friday.")
        XCTAssertEqual(fillers("Um, let's go."), "Let's go.")
        XCTAssertEqual(fillers("I think uh it works"), "I think it works")
    }

    func testYouKnowGoesOnlyWhenItIsAFiller() {
        XCTAssertEqual(fillers("He was a strategic, you know, manager."), "He was a strategic manager.")
        XCTAssertEqual(fillers("It's hard, you know."), "It's hard.")
        XCTAssertEqual(fillers("You know, I think so."), "I think so.")
        XCTAssertEqual(fillers("Use everything you know about it."), "Use everything you know about it.")
        XCTAssertEqual(fillers("You know what I mean?"), "You know what I mean?")
    }

    func testSentencesThatHadNoFillerAreUntouched() {
        XCTAssertEqual(fillers("iPhone sales are up. eBay too."), "iPhone sales are up. eBay too.")
    }

    func testLargerNumbersBecomeDigits() {
        XCTAssertEqual(numbers("Give it ninety days."), "Give it 90 days.")
        XCTAssertEqual(numbers("We need twenty-five seats"), "We need 25 seats")
        XCTAssertEqual(numbers("about twenty five people"), "about 25 people")
        XCTAssertEqual(numbers("one hundred twenty three emails"), "123 emails")
        XCTAssertEqual(numbers("two thousand five hundred calls"), "2,500 calls")
        XCTAssertEqual(numbers("Seven day, thirty day, or more"), "Seven day, 30 day, or more")
    }

    func testSmallNumbersStayAsWords() {
        XCTAssertEqual(numbers("at least two, maybe four tickets."), "at least two, maybe four tickets.")
        XCTAssertEqual(numbers("one of them said three to four X lower cost"), "one of them said three to four X lower cost")
    }

    func testPercentAndDollars() {
        XCTAssertEqual(numbers("Apply a fifty percent blur"), "Apply a 50% blur")
        XCTAssertEqual(numbers("A hundred percent."), "100%.")
        XCTAssertEqual(numbers("never more than a hundred and sixty dollars for this"), "never more than $160 for this")
        XCTAssertEqual(numbers("only five percent"), "only 5%")
        XCTAssertEqual(numbers("Apply a 50 percent blur"), "Apply a 50% blur")
    }

    func testYearsAndMillions() {
        XCTAssertEqual(numbers("Did I purchase in twenty twenty?"), "Did I purchase in 2020?")
        XCTAssertEqual(numbers("Q4 of twenty twenty-six"), "Q4 of 2026")
        XCTAssertEqual(numbers("back in nineteen ninety nine"), "back in 1999")
        XCTAssertEqual(numbers("nineteen hundred"), "1900")
        XCTAssertEqual(numbers("twenty two thousand users"), "22,000 users")
        XCTAssertEqual(numbers("two million users"), "2 million users")
    }

    func testCapitalizedNumberWordsInNamesStay() {
        XCTAssertEqual(numbers("cheaper than Eleven Labs."), "cheaper than Eleven Labs.")
        XCTAssertEqual(numbers("We watched Ocean's Twelve. Twenty people came."), "We watched Ocean's Twelve. 20 people came.")
    }

    func testDigitsAndWordsWithoutNumbersAreUntouched() {
        XCTAssertEqual(numbers("It's 2.11 million short of the 8.1 million goal."), "It's 2.11 million short of the 8.1 million goal.")
        XCTAssertEqual(numbers("Can someone take a look? And then hundreds of them."), "Can someone take a look? And then hundreds of them.")
    }

    func testTheSwitchesTurnEachStepOff() {
        let text = "Um, give it ninety days."
        XCTAssertEqual(TranscriptCleanup.clean(text, removeFillers: true, formatNumbers: true), "Give it 90 days.")
        XCTAssertEqual(TranscriptCleanup.clean(text, removeFillers: false, formatNumbers: false), text)
    }
}
