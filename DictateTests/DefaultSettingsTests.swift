import XCTest
@testable import Dictate

/// What someone who has never opened Settings gets.
final class DefaultSettingsTests: XCTestCase {
    private let keys = [
        DictationLanguage.storageKey, DictationListenMode.storageKey, TranscriptCleanup.removeFillersKey,
        TranscriptCleanup.formatNumbersKey, ScreenContext.enabledKey, PastePreferences.trailingSpaceKey,
        SpokenRepair.repairKey, SpokenRepair.polishKey,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            UserDefaults.standard.set(saved[key], forKey: key)
        }
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertEqual(DictationLanguage.storedCode, "en")
        XCTAssertEqual(DictationListenMode.current, .holdOrTap)
        XCTAssertTrue(TranscriptCleanup.removeFillers)
        XCTAssertTrue(TranscriptCleanup.formatNumbers)
        XCTAssertTrue(ScreenContext.isEnabled)
        XCTAssertTrue(PastePreferences.addTrailingSpace)
        XCTAssertFalse(SpokenRepair.repairIsOn())
        XCTAssertFalse(SpokenRepair.polishIsOn())
    }

    func testChoosingAutoDetectSticks() {
        UserDefaults.standard.set("", forKey: DictationLanguage.storageKey)
        XCTAssertNil(DictationLanguage.storedCode)
    }

    func testUpdatesCheckAndInstallOnTheirOwn() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, true)
    }
}
