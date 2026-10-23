import AVFoundation
import XCTest
@testable import Dictate

final class PCMConversionTests: XCTestCase {
    func testLinear16PacksLittleEndianSamples() throws {
        let format = try XCTUnwrap(PCMConversion.targetFormat())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2
        buffer.int16ChannelData![0][0] = 255
        buffer.int16ChannelData![0][1] = -2

        let data = try XCTUnwrap(PCMConversion.linear16Data(from: buffer))

        XCTAssertEqual(Array(data), [0xFF, 0x00, 0xFE, 0xFF])
    }

    func testSilenceConvertsToEvenQuiet16kHzPCM() throws {
        let data = try convert(frames: 4_800, sampleRate: 48_000) { _, _ in 0 }

        XCTAssertEqual(data.count % 2, 0)
        XCTAssertGreaterThan(data.count, 2_400)
        XCTAssertLessThan(data.count, 4_000)
        XCTAssertTrue(samples(in: data).allSatisfy { abs($0) < 32 })
    }

    func testToneConvertsToNonZeroSamples() throws {
        let data = try convert(frames: 4_800, sampleRate: 48_000) { index, _ in
            sin(2 * .pi * 440 * Double(index) / 48_000) * 0.4
        }

        XCTAssertEqual(data.count % 2, 0)
        XCTAssertTrue(samples(in: data).contains { abs($0) > 500 })
    }

    private func convert(
        frames: AVAudioFrameCount,
        sampleRate: Double,
        sample: (Int, AVAudioFrameCount) -> Double
    ) throws -> Data {
        let source = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        )
        let target = try XCTUnwrap(PCMConversion.targetFormat())
        let converter = try XCTUnwrap(AVAudioConverter(from: source, to: target))
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            channel[index] = Float(sample(index, frames))
        }
        return try XCTUnwrap(PCMConversion.convert(buffer, using: converter, to: target))
    }

    private func samples(in data: Data) -> [Int16] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self))
        }
    }
}
