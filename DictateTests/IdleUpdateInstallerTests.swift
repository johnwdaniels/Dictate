import XCTest
@testable import Dictate

@MainActor
final class IdleUpdateInstallerTests: XCTestCase {
    func testWaitsForThreeIdleMinutes() {
        XCTAssertFalse(IdleUpdateInstaller.shouldInstall(idleSeconds: 179, busy: false))
        XCTAssertTrue(IdleUpdateInstaller.shouldInstall(idleSeconds: 180, busy: false))
    }

    func testNeverInterruptsADictation() {
        XCTAssertFalse(IdleUpdateInstaller.shouldInstall(idleSeconds: 3_600, busy: true))
    }
}
