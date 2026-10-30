import XCTest
@testable import Dictate

final class ScreenContextTests: XCTestCase {
    private let english: Set<String> = [
        "with", "the", "duo", "message", "send", "reply", "today", "pedro", "will", "a",
    ]
    private func isKnown(_ word: String) -> Bool { english.contains(word) }

    func testPicksUnusualCapitalizedWordsInReadingOrder() {
        let strings = [
            "Kylan Ostrowski", "Message", "Reply to Kylan", "Send", "SEND", "October", "Japanese", "Germany", "Zhaoyi wrote today",
        ]
        XCTAssertEqual(ScreenContext.terms(in: strings, isKnownWord: isKnown), ["Kylan", "Ostrowski", "Zhaoyi"])
    }

    func testPicksAcronymsInnerCapitalsAndLettersWithDigits() {
        let strings = [
            "Sign the MSA and ZDR (SEND)", "Try GPT-4o on your iPhone, B2B v1.4.2 at 10am", "ElevenLabs’s ad",
            "Dictate-v1.4.2.zip C0C7P92UYGM cus_VVxtRgh querySelectorAll",
        ]
        XCTAssertEqual(
            ScreenContext.terms(in: strings, isKnownWord: { $0 == "send" || $0 == "sign" || $0 == "try" }),
            ["MSA", "ZDR", "GPT-4o", "iPhone", "B2B", "ElevenLabs"]
        )
    }

    func testCurlyApostrophesBecomeStraight() {
        let strings = ["I haven’t met Siobhan O’Brien or Kylan’s team", "D’Angelo’s ‘Voodoo’"]
        let terms = ScreenContext.terms(in: strings, isKnownWord: isKnown)
        XCTAssertEqual(terms, ["Siobhan", "O'Brien", "Kylan", "D'Angelo", "Voodoo"])
        XCTAssertTrue(terms.allSatisfy(DictionaryTermRules.isAllowed))
    }

    func testCorrectsANearMissToTheScreenSpelling() {
        let terms = ["Kylan", "Ostrowski"]
        XCTAssertEqual(
            ScreenContext.correctingNames("Thanks Kylen, talk to Ostrowsky soon", using: terms, isKnownWord: isKnown),
            "Thanks Kylan, talk to Ostrowski soon"
        )
    }

    func testLeavesRealWordsAndFarMissesAlone() {
        let terms = ["Kylan"]
        XCTAssertEqual(ScreenContext.correctingNames("With the duo", using: terms, isKnownWord: isKnown), "With the duo")
        XCTAssertEqual(ScreenContext.correctingNames("Kenneth said", using: terms, isKnownWord: isKnown), "Kenneth said")
    }

    func testATieMeansNoSwap() {
        XCTAssertEqual(
            ScreenContext.correctingNames("Hi Kalen", using: ["Kalan", "Kalin"], isKnownWord: isKnown),
            "Hi Kalen"
        )
    }

    func testMergedKeepsDictionaryFirstWithoutRepeats() {
        XCTAssertEqual(InworldSTTClient.merged(["Inworld", "Kylan"], ["kylan", "Zhaoyi"]), ["Inworld", "Kylan", "Zhaoyi"])
    }

    func testLowercasesMidSentenceButKeepsNames() {
        XCTAssertTrue(SmartSpacing.continuesSentence("duo "))
        XCTAssertTrue(SmartSpacing.continuesSentence("in,"))
        XCTAssertFalse(SmartSpacing.continuesSentence("in. "))
        XCTAssertFalse(SmartSpacing.continuesSentence("done?” "))
        XCTAssertFalse(SmartSpacing.continuesSentence("end\n"))
        XCTAssertFalse(SmartSpacing.continuesSentence(""))

        let lower = { (text: String, names: Set<String>) in
            SmartSpacing.lowercasingFirstWord(text, keeping: names, isKnownWord: self.isKnown)
        }
        XCTAssertEqual(lower("With the duo", []), "with the duo")
        XCTAssertEqual(lower("I think so", []), "I think so")
        XCTAssertEqual(lower("NASA called", []), "NASA called")
        XCTAssertEqual(lower("Kylan said yes", []), "Kylan said yes")
        XCTAssertEqual(lower("Pedro said yes", []), "pedro said yes")
        XCTAssertEqual(lower("Pedro said yes", ["Pedro"]), "Pedro said yes")
    }
}
