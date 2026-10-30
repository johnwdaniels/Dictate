import AppKit
import XCTest
@testable import Dictate

final class StartSoundTests: XCTestCase {
    func testEverySoundShipsAFileThatMatchesItsDuration() throws {
        for sound in StartSound.allCases where sound != .off {
            let url = try XCTUnwrap(sound.fileURL, "\(sound.rawValue).wav is missing from the app bundle")
            let file = try XCTUnwrap(NSSound(contentsOf: url, byReference: false))
            XCTAssertEqual(file.duration, sound.duration, accuracy: 0.005, sound.rawValue)
        }
    }

    func testSoundsStayShort() {
        for sound in StartSound.allCases {
            XCTAssertLessThanOrEqual(sound.duration, 0.35, sound.rawValue)
        }
    }

    func testOldChoicesFallBackToSoftLift() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: StartSound.storageKey)
        defer { defaults.set(saved, forKey: StartSound.storageKey) }

        defaults.set("ding", forKey: StartSound.storageKey)
        XCTAssertEqual(StartSound.current, .softLift)
        defaults.set("off", forKey: StartSound.storageKey)
        XCTAssertEqual(StartSound.current, .off)
    }

    func testARetiredChoiceIsRewrittenAndCurrentOnesAreKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StartSoundTests"))
        defer { defaults.removePersistentDomain(forName: "StartSoundTests") }

        defaults.set("ding", forKey: StartSound.storageKey)
        StartSound.retireOldChoice(in: defaults)
        XCTAssertEqual(defaults.string(forKey: StartSound.storageKey), StartSound.softLift.rawValue)

        defaults.set("off", forKey: StartSound.storageKey)
        StartSound.retireOldChoice(in: defaults)
        XCTAssertEqual(defaults.string(forKey: StartSound.storageKey), "off")

        defaults.removeObject(forKey: StartSound.storageKey)
        StartSound.retireOldChoice(in: defaults)
        XCTAssertNil(defaults.string(forKey: StartSound.storageKey))
    }
}
