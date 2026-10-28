import XCTest
@testable import Dictate

final class InputDevicesTests: XCTestCase {
    private let devices = [
        InputDevices.Device(id: 41, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"),
        InputDevices.Device(id: 87, uid: "AppleUSBAudioEngine:Shure:MV7", name: "Shure MV7"),
    ]

    func testAConnectedChoiceIsUsed() {
        XCTAssertEqual(InputDevices.resolvedInputID(selectedUID: "AppleUSBAudioEngine:Shure:MV7", devices: devices), 87)
    }

    func testNoChoiceUsesTheSystemDefault() {
        XCTAssertEqual(InputDevices.resolvedInputID(selectedUID: "", devices: devices), InputDevices.defaultInputID())
    }

    func testAnUnpluggedChoiceFallsBackToTheSystemDefault() {
        XCTAssertEqual(InputDevices.resolvedInputID(selectedUID: "Unplugged:USB:Mic", devices: devices), InputDevices.defaultInputID())
    }

    func testListedDevicesHaveNamesAndDistinctIDs() {
        let listed = InputDevices.all()
        XCTAssertTrue(listed.allSatisfy { !$0.name.isEmpty && !$0.uid.isEmpty })
        XCTAssertEqual(Set(listed.map(\.uid)).count, listed.count)
        print("Input devices:", listed.map { "\($0.name) [\($0.uid)]" })
    }
}
