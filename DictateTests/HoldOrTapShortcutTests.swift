import XCTest
@testable import Dictate

final class HoldOrTapShortcutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testATapKeepsRecordingUntilTheNextPress() {
        var shortcut = HoldOrTapShortcut()
        XCTAssertEqual(shortcut.pressed(at: start, phase: .idle), .start)
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(0.15), phase: .recording), .nothing)

        XCTAssertEqual(shortcut.pressed(at: start.addingTimeInterval(5), phase: .recording), .stop)
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(5.1), phase: .processing), .nothing)
    }

    func testAHoldStopsWhenReleased() {
        var shortcut = HoldOrTapShortcut()
        XCTAssertEqual(shortcut.pressed(at: start, phase: .idle), .start)
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(2), phase: .recording), .stop)
    }

    func testTheThresholdSeparatesATapFromAHold() {
        var tap = HoldOrTapShortcut()
        _ = tap.pressed(at: start, phase: .idle)
        let justUnder = start.addingTimeInterval(HoldOrTapShortcut.holdThreshold - 0.01)
        XCTAssertEqual(tap.released(at: justUnder, phase: .recording), .nothing)

        var hold = HoldOrTapShortcut()
        _ = hold.pressed(at: start, phase: .idle)
        let justOver = start.addingTimeInterval(HoldOrTapShortcut.holdThreshold + 0.01)
        XCTAssertEqual(hold.released(at: justOver, phase: .recording), .stop)
    }

    func testTheReleaseAfterAStoppingPressDoesNothing() {
        var shortcut = HoldOrTapShortcut()
        _ = shortcut.pressed(at: start, phase: .idle)
        _ = shortcut.released(at: start.addingTimeInterval(0.1), phase: .recording)

        // A long press that stops an open recording must not also count as a hold on release.
        XCTAssertEqual(shortcut.pressed(at: start.addingTimeInterval(3), phase: .recording), .stop)
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(4), phase: .processing), .nothing)
    }

    func testPressesWhileProcessingAreIgnored() {
        var shortcut = HoldOrTapShortcut()
        XCTAssertEqual(shortcut.pressed(at: start, phase: .processing), .nothing)
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(1), phase: .processing), .nothing)
    }

    func testAReleaseAfterTheRecordingEndedOnItsOwnDoesNothing() {
        var shortcut = HoldOrTapShortcut()
        _ = shortcut.pressed(at: start, phase: .idle)
        // A missing key or a failed connection can end the recording while the keys are still held.
        XCTAssertEqual(shortcut.released(at: start.addingTimeInterval(1), phase: .idle), .nothing)
        XCTAssertEqual(shortcut.pressed(at: start.addingTimeInterval(2), phase: .idle), .start)
    }
}
