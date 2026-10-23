import AVFoundation
import Foundation

/// Converts microphone buffers to the 16 kHz mono LINEAR16 bytes Inworld expects.
enum PCMConversion {
    static func targetFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )
    }

    static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let estimated = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(estimated, 1)) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status != .error else { return nil }
        return linear16Data(from: output)
    }

    static func linear16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0, let samples = buffer.int16ChannelData else { return nil }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: samples[0], count: byteCount)
    }
}
