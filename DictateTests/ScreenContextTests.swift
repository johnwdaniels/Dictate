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

    @MainActor
    func testFirstNamesTheSpellCheckerAcceptsStillCountAsNames() throws {
        for word in ["email", "website", "settings", "message"] {
            XCTAssertTrue(ScreenContext.isEnglishWord(word), word)
        }
        // Some Macs, such as CI's, list no completions, and the check falls back to the spell checker alone.
        try XCTSkipIf(ScreenContext.completionLanguage == nil, "No spell checker completions on this Mac")
        for name in ["nikki", "jessica", "liam"] {
            XCTAssertFalse(ScreenContext.isEnglishWord(name), name)
        }
        let candidates = ScreenContext.candidates(in: ["Message Nikki", "Settings"], wordList: [])
        XCTAssertEqual(ScreenContext.terms(from: candidates), ["Nikki"])
    }

    func testRareWordListWordsTheSpellCheckerDoesntKnowStayTerms() {
        let candidates = ScreenContext.candidates(in: ["Arx Media", "Reply"], wordList: ["arx", "media", "reply"])
        let terms = ScreenContext.terms(
            from: candidates, isKnownWord: { _ in true }, isSpelledWord: { $0 == "media" || $0 == "reply" }
        )
        XCTAssertEqual(terms, ["Arx"])
    }

    func testHintsUseTheWholeCompanyName() {
        let strings = ["Reply to Nikki about the Arx Media deal", "PocketFM and Arx Media, Inworld"]
        let terms = ["Nikki", "Arx", "PocketFM", "Inworld"]
        let phrases = ScreenContext.phrases(in: strings, containing: terms)
        XCTAssertEqual(phrases, ["Arx Media"])
        XCTAssertEqual(ScreenContext.hints(from: terms, phrases: phrases), ["Nikki", "Arx Media", "PocketFM", "Inworld"])
    }

    func testLongTitleCaseLabelsAreNotPhrases() {
        XCTAssertEqual(ScreenContext.phrases(in: ["Talk To Arx Media Team Right Now"], containing: ["Arx"]), [])
    }

    func testJoinsATermSaidInPieces() {
        XCTAssertEqual(
            ScreenContext.correctingNames(
                "Send it to pocket FM and Eleven Labs", using: ["PocketFM", "ElevenLabs"], isKnownWord: isKnown
            ),
            "Send it to PocketFM and ElevenLabs"
        )
    }

    func testFixesAMisheardWordInAScreenPhraseOnly() {
        let fix = { (text: String) in
            ScreenContext.correctingNames(
                text, using: ["Arx", "Nikki"], phrases: ["Arx Media"], isKnownWord: { $0 == "arcs" || $0 == "talk" }
            )
        }
        XCTAssertEqual(fix("I met Nicki at Arcs Media"), "I met Nikki at Arx Media")
        XCTAssertEqual(fix("arcs media signed"), "Arx media signed")
        XCTAssertEqual(fix("Talk to Arcs about it"), "Talk to Arcs about it")
        XCTAssertEqual(fix("arcs of light"), "arcs of light")
    }

    func testSoundKey() {
        XCTAssertEqual(ScreenContext.soundKey("arcs"), ScreenContext.soundKey("Arx"))
        XCTAssertEqual(ScreenContext.soundKey("Nicki"), ScreenContext.soundKey("Nikki"))
        XCTAssertNotEqual(ScreenContext.soundKey("Ask"), ScreenContext.soundKey("Arx"))
    }
}
