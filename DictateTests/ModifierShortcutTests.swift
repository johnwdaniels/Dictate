import Carbon.HIToolbox
import KeyboardShortcuts
import XCTest
@testable import Dictate

final class ModifierShortcutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testAHoldReportsAPressThenAReleaseAtTheRealTimes() {
        var tracker = ModifierTapTracker()
        XCTAssertEqual(tracker.modifierDown(at: start), [.armed(start)])
        XCTAssertEqual(tracker.holdElapsed(), [.pressed(start)])
        XCTAssertEqual(tracker.modifierUp(at: start.addingTimeInterval(2)), [.released(start.addingTimeInterval(2))])
    }

    func testAQuickTapReportsBothWhenTheKeyComesUp() {
        var tracker = ModifierTapTracker()
        _ = tracker.modifierDown(at: start)
        let up = start.addingTimeInterval(0.08)
        XCTAssertEqual(tracker.modifierUp(at: up), [.pressed(start), .released(up)])
    }

    func testAChordLikeOptionEIsNotAShortcut() {
        var tracker = ModifierTapTracker()
        _ = tracker.modifierDown(at: start)
        XCTAssertEqual(tracker.otherInput(), [.disarmed])
        XCTAssertEqual(tracker.otherInput(), [])
        XCTAssertEqual(tracker.holdElapsed(), [])
        XCTAssertEqual(tracker.modifierUp(at: start.addingTimeInterval(0.3)), [])
    }

    func testTypingAfterDictationStartedDoesNotCancelIt() {
        var tracker = ModifierTapTracker()
        _ = tracker.modifierDown(at: start)
        _ = tracker.holdElapsed()
        XCTAssertEqual(tracker.otherInput(), [])
        XCTAssertEqual(tracker.modifierUp(at: start.addingTimeInterval(1)), [.released(start.addingTimeInterval(1))])
    }

    func testTheHoldDelayFiresOnlyOnce() {
        var tracker = ModifierTapTracker()
        _ = tracker.modifierDown(at: start)
        _ = tracker.holdElapsed()
        XCTAssertEqual(tracker.holdElapsed(), [])
    }

    func testRightKeysAreToldApartFromLeftKeys() {
        XCTAssertEqual(ModifierKey(keyCode: kVK_RightOption), .rightOption)
        XCTAssertNil(ModifierKey(keyCode: kVK_Option))
        XCTAssertTrue(ModifierKey.leftKeyCodes.contains(kVK_Option))

        let rightOptionDown = NSEvent.ModifierFlags.option.rawValue | 0x40
        let leftOptionDown = NSEvent.ModifierFlags.option.rawValue | 0x20
        XCTAssertTrue(ModifierKey.rightOption.isDown(flags: rightOptionDown))
        XCTAssertFalse(ModifierKey.rightOption.isDown(flags: leftOptionDown))
    }

    func testTheChoiceIsSavedPerShortcut() {
        let defaults = UserDefaults(suiteName: "ModifierShortcutTests")!
        defaults.removePersistentDomain(forName: "ModifierShortcutTests")
        ModifierKey.store(.rightOption, for: .startDictation, in: defaults)
        XCTAssertEqual(ModifierKey.stored(for: .startDictation, in: defaults), .rightOption)
        XCTAssertNil(ModifierKey.stored(for: .openRecording, in: defaults))
        ModifierKey.store(nil, for: .startDictation, in: defaults)
        XCTAssertNil(ModifierKey.stored(for: .startDictation, in: defaults))
        defaults.removePersistentDomain(forName: "ModifierShortcutTests")
    }
}
