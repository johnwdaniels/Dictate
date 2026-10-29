import XCTest
@testable import Dictate

final class StartGateTests: XCTestCase {
    func testWithASoundAudioStartsWhenTheSoundEnds() {
        let start = StartGate.forwardStart(cue: 100, ring: 0.26, keepFrom: nil)
        XCTAssertEqual(start, 100 + 0.26 + StartGate.soundTail, accuracy: 0.0001)
    }

    func testWithoutASoundEverythingFromKeyDownIsSent() {
        XCTAssertEqual(StartGate.forwardStart(cue: 100.15, ring: 0, keepFrom: 100), 100)
        XCTAssertEqual(StartGate.forwardStart(cue: 100, ring: 0, keepFrom: nil), 0)
    }

    func testTheGateWaitsUntilOpened() {
        let gate = StartGate(keepFrom: 100)
        XCTAssertEqual(gate.state, .waiting)
        XCTAssertEqual(gate.forwardFrom, .infinity)
        gate.open(cue: 100.15, ring: 0)
        XCTAssertEqual(gate.state, .open)
        XCTAssertEqual(gate.forwardFrom, 100)
    }

    func testACancelledGateStaysCancelled() {
        let gate = StartGate(keepFrom: 100)
        gate.cancel()
        gate.open(cue: 100.15, ring: 0)
        XCTAssertEqual(gate.state, .cancelled)
        XCTAssertEqual(gate.forwardFrom, .infinity)
    }

    func testAnOpenGateIgnoresALateCancel() {
        let gate = StartGate()
        gate.open(cue: 100, ring: 0.1)
        gate.cancel()
        XCTAssertEqual(gate.state, .open)
    }
}
