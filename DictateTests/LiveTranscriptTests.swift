import XCTest
@testable import Dictate

final class LiveTranscriptTests: XCTestCase {
    func testThePartialGrowsInPlace() {
        let live = LiveTranscript()
        XCTAssertEqual(live.showing(partial: "Please open"), "Please open")
        XCTAssertEqual(live.showing(partial: "Please open the door"), "Please open the door")
    }

    func testFinishedPhrasesStayWhileTheNextOneStreams() {
        var live = LiveTranscript()
        XCTAssertEqual(live.finish("Please open the door."), "Please open the door.")
        XCTAssertEqual(live.showing(partial: "And turn"), "Please open the door. And turn")
        XCTAssertEqual(live.showing(partial: "And turn on the lights"), "Please open the door. And turn on the lights")
        XCTAssertEqual(live.finish("And turn on the lights."), "Please open the door. And turn on the lights.")
    }

    func testAnEmptyFinalFromADroppedEchoChangesNothing() {
        var live = LiveTranscript()
        _ = live.finish("Ship it.")
        XCTAssertEqual(live.finish(""), "Ship it.")
        XCTAssertEqual(live.showing(partial: ""), "Ship it.")
    }
}
