import AVFoundation
import Foundation
import os

/// Captures the default microphone and yields 16-bit little-endian PCM at 16 kHz, mono.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let forwarding = OSAllocatedUnfairLock(initialState: false)
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var continuation: AsyncStream<Data>.Continuation?
    private var tapInstalled = false
    private var lastLevelSent = CFAbsoluteTime(0)

    /// Called on the main queue, at most 30 times a second, with a level from 0 (silence) to 1.
    var onLevel: (@Sendable (Float) -> Void)?

    func start() async throws -> AsyncStream<Data> {
        guard await requestAccess() else {
            throw InworldSTTError.microphoneDenied
        }
        return try await MainActor.run {
            try self.openEngine()
        }
    }

    /// Audio captured after `start` is kept on the mic meter only. Call this once the start bell has finished so that sound is not transcribed.
    func beginForwarding() {
        forwarding.withLock { $0 = true }
    }

    /// Stops the microphone. Safe on the main thread. From any other thread it hops to the main queue without waiting, so it cannot deadlock a thread that the main queue needs.
    func stop() {
        if Thread.isMainThread {
            closeEngine()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.closeEngine()
            }
        }
    }

    /// Stops the microphone and returns after the tap is removed.
    func stopAndWait() async {
        await MainActor.run {
            closeEngine()
        }
    }

    private func openEngine() throws -> AsyncStream<Data> {
        closeEngine()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw InworldSTTError.audioFormatUnavailable
        }
        guard let targetFormat = PCMConversion.targetFormat(),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw InworldSTTError.audioFormatUnavailable
        }

        self.targetFormat = targetFormat
        self.converter = converter

        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.publishLevel(buffer)
            let yieldAudio = self.forwarding.withLock { $0 }
            guard yieldAudio, let data = self.convert(buffer) else { return }
            self.continuation?.yield(data)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            closeEngine()
            throw error
        }
        return stream
    }

    private func closeEngine() {
        forwarding.withLock { $0 = false }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter = nil
        targetFormat = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.finish()
    }

    private func publishLevel(_ buffer: AVAudioPCMBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelSent >= 1.0 / 30 else { return }
        lastLevelSent = now
        let level = Self.normalizedLevel(buffer)
        guard let onLevel else { return }
        DispatchQueue.main.async {
            onLevel(level)
        }
    }

    /// Maps microphone RMS into 0...1. Quiet rooms sit near 0, normal speech fills the meter.
    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        var count = 0
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<frames {
                let sample = samples[index]
                sum += sample * sample
            }
            count = frames
        } else if let samples = buffer.int16ChannelData?[0] {
            let step = 4
            var index = 0
            while index < frames {
                let sample = Float(samples[index]) / Float(Int16.max)
                sum += sample * sample
                count += 1
                index += step
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(1, max(0, (decibels + 52) / 38))
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter, let targetFormat else { return nil }
        return PCMConversion.convert(buffer, using: converter, to: targetFormat)
    }
}
