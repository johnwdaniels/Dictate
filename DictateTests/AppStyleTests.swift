import XCTest
@testable import Dictate

final class AppStyleTests: XCTestCase {
    private let messages = "com.apple.MobileSMS"
    private let slack = "com.tinyspeck.slackmacgap"
    private let mail = "com.apple.mail"
    private let notes = "com.apple.Notes"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AppStyleTests")
        defaults.removePersistentDomain(forName: "AppStyleTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "AppStyleTests")
        super.tearDown()
    }

    func testDefaultsAreCasualForChatAndProfessionalElsewhere() {
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: messages, in: defaults), "On my way")
        XCTAssertEqual(AppStyle.styled("Sounds good. See you at 5.", bundleID: slack, in: defaults), "Sounds good. See you at 5")
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: mail, in: defaults), "On my way.")
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: notes, in: defaults), "On my way.")
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: "", in: defaults), "On my way.")
    }

    func testAChosenStyleIsUsedForItsCategory() {
        defaults.set(WritingStyle.professional.rawValue, forKey: AppCategory.personal.styleKey)
        defaults.set(WritingStyle.veryCasual.rawValue, forKey: AppCategory.other.styleKey)
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: messages, in: defaults), "On my way.")
        XCTAssertEqual(AppStyle.styled("On my way.", bundleID: notes, in: defaults), "on my way")
    }

    func testMovingAnAppTakesItOutOfItsOldCategory() {
        AppStyle.move(slack, to: .personal, in: defaults)
        XCTAssertEqual(AppStyle.category(for: slack, in: defaults), .personal)
        XCTAssertFalse(AppStyle.bundleIDs(for: .work, in: defaults).contains(slack))

        AppStyle.remove(slack, from: .personal, in: defaults)
        XCTAssertEqual(AppStyle.category(for: slack, in: defaults), .other)
    }

    func testTheSampleReadsDifferentlyInEachStyle() {
        XCTAssertEqual(AppStyle.apply(.professional, to: AppStyle.sample), "Hey, are you free tomorrow? Let's grab lunch.")
        XCTAssertEqual(AppStyle.apply(.casual, to: AppStyle.sample), "Hey, are you free tomorrow? Let's grab lunch")
        XCTAssertEqual(AppStyle.apply(.veryCasual, to: AppStyle.sample), "hey, are you free tomorrow? let's grab lunch")
    }

    func testQuestionsExclamationsAndEllipsesStay() {
        XCTAssertEqual(AppStyle.droppingFinalPeriod("Are you coming?"), "Are you coming?")
        XCTAssertEqual(AppStyle.droppingFinalPeriod("That's great!"), "That's great!")
        XCTAssertEqual(AppStyle.droppingFinalPeriod("Well..."), "Well...")
        XCTAssertEqual(AppStyle.droppingFinalPeriod("Well…"), "Well…")
        XCTAssertEqual(AppStyle.droppingFinalPeriod("."), ".")
    }

    func testVeryCasualKeepsIAndAcronyms() {
        XCTAssertEqual(AppStyle.lowercasingSentenceStarts("I think so. NASA called. I'm in."), "I think so. NASA called. I'm in.")
        XCTAssertEqual(AppStyle.lowercasingSentenceStarts("Okay. Then we go. Right?"), "okay. then we go. right?")
    }
}
