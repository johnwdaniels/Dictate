import XCTest
@testable import Dictate

final class TranscriptCleanupTests: XCTestCase {
    private func fillers(_ text: String) -> String { TranscriptCleanup.removingFillers(text) }
    private func numbers(_ text: String) -> String { TranscriptCleanup.formattingNumbers(text) }
    private func codes(_ text: String) -> String { TranscriptCleanup.joiningSpelledCodes(text) }

    func testSpelledOutCodesAreJoined() {
        XCTAssertEqual(codes("My code is P-E-C-2-6-B-A-4-9-7."), "My code is PEC26BA497.")
        XCTAssertEqual(codes("Use A B 1 2 C D to log in"), "Use AB12CD to log in")
        XCTAssertEqual(codes("Call 5 5 5 1 2 3 4 5 6 7 tomorrow"), "Call 5551234567 tomorrow")
        XCTAssertEqual(codes("Made in the U-S-A, shipped to the U-K-"), "Made in the USA, shipped to the U-K-")
        XCTAssertEqual(codes("Codes X-1-Y-2 and 9-8-7-6"), "Codes X1Y2 and 9876")
    }

    func testOrdinaryTextIsNotTreatedAsACode() {
        let untouched = [
            "I need a 5 minute break.",
            "Plan A B is fine, and so is option 1 2 3.",
            "Call 555-123-4567 on 2026-10-29 about v1.7.3.",
            "The COVID-19 numbers and the T-shirt in size M.",
            "Grades went A B C D over the year.",
            "Pick between A and B, then press 1 or 2.",
        ]
        for text in untouched {
            XCTAssertEqual(codes(text), text)
        }
    }

    func testTheCodeSwitchTurnsJoiningOff() {
        let text = "Code P-E-C-2-6"
        XCTAssertEqual(TranscriptCleanup.clean(text, removeFillers: false, formatNumbers: false, joinCodes: true), "Code PEC26")
        XCTAssertEqual(TranscriptCleanup.clean(text, removeFillers: false, formatNumbers: false, joinCodes: false), text)
    }

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

    // MARK: Stray characters

    private func stray(_ text: String, language: String? = "en") -> String {
        TranscriptCleanup.removingStrayCJK(text, language: language)
    }

    func testAHesitationWrittenAsChineseIsDropped() {
        XCTAssertEqual(stray("嗯。 I haven't ordered any of that."), "I haven't ordered any of that.")
        XCTAssertEqual(stray("嗯。I haven't ordered any of that."), "I haven't ordered any of that.")
        XCTAssertEqual(stray("呃 let's go"), "Let's go")
        XCTAssertEqual(stray("See you at lunch. 嗯。"), "See you at lunch.")
        XCTAssertEqual(stray("嗯。 I haven't ordered any of that.", language: nil), "I haven't ordered any of that.")
    }

    func testItRunsEvenWithTheCleanupSwitchesOff() {
        XCTAssertEqual(TranscriptCleanup.clean("嗯。 Ship it.", removeFillers: false, formatNumbers: false, language: "en"), "Ship it.")
    }

    func testChineseSaidOnPurposeStays() {
        XCTAssertEqual(stray("The word 你好 means hello."), "The word 你好 means hello.")
        XCTAssertEqual(stray("嗯，我觉得可以。"), "嗯，我觉得可以。")
        XCTAssertEqual(stray("嗯。 I think so.", language: "zh"), "嗯。 I think so.")
        XCTAssertEqual(stray("你好世界 is a long greeting"), "你好世界 is a long greeting")
    }

    func testAHesitationWrittenAsALoneLetterIsDropped() {
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("É. I like owner.", language: "en"), "I like owner.")
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("Ö. Ship it.", language: nil), "Ship it.")
        XCTAssertEqual(TranscriptCleanup.clean("É. I like owner.", removeFillers: false, formatNumbers: false, language: "en"), "I like owner.")
    }

    func testRealOneLetterWordsAndOtherLanguagesStay() {
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("I. Agree with that.", language: "en"), "I. Agree with that.")
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("A. Then B.", language: "en"), "A. Then B.")
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("É. Eu acho que sim.", language: "pt"), "É. Eu acho que sim.")
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("É. Não sei.", language: nil), "É. Não sei.")
        XCTAssertEqual(TranscriptCleanup.removingStrayLetter("Plan B. Ship it.", language: "en"), "Plan B. Ship it.")
    }

    func testEhIsAFiller() {
        XCTAssertEqual(fillers("Eh, let's go."), "Let's go.")
    }
}
