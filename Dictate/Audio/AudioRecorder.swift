import AVFoundation
import Foundation

/// 16 kHz mono PCM with the time it was captured, so a session can skip audio from before its start cue.
struct AudioChunk: Sendable {
    let time: CFAbsoluteTime
    let data: Data
}

/// Captures the microphone chosen in Settings, or the system default, and yields 16-bit little-endian PCM at 16 kHz, mono.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var inputDeviceID: AudioDeviceID?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var tapInstalled = false
    private var lastLevelSent = CFAbsoluteTime(0)
    private let flowLock = NSLock()
    private var flowing = false
    private var flowWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cycleNotifyUnit: AudioUnit?
    /// Read and written only on the audio thread while the engine runs, and reset before it starts.
    fileprivate var cycleSeen = false
    private var lingerClose: DispatchWorkItem?

    /// How long the mic stays open after a dictation, with its audio dropped. Restarting some inputs within about a
    /// second of stopping them (a Loopback device on an audio interface, for one) glitches the speakers, and the start
    /// sound pops. A dictation inside this window reuses the open mic: no restart, no pop, and no start-up wait.
    static let linger: TimeInterval = 5

    /// Called on the main queue, at most 30 times a second, with a level from 0 (silence) to 1.
    var onLevel: (@Sendable (Float) -> Void)?

    /// Every chunk from the moment the microphone opens. The stream holds them until the caller is ready to read.
    func start() async throws -> AsyncStream<AudioChunk> {
        guard await requestAccess() else {
            throw InworldSTTError.microphoneDenied
        }
        return try await MainActor.run {
            if let stream = self.reuseOpenMic() {
                return stream
            }
            return try self.openEngine()
        }
    }

    /// Returns on the mic hardware's first processing cycle, the earliest moment it is really running, a few ms in.
    /// `start()` returns earlier, while a headset or an audio interface may still be switching over. Gives up after `timeout`.
    func waitUntilRunning(timeout: TimeInterval = 0.5) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let id = UUID()
            flowLock.lock()
            guard !flowing else {
                flowLock.unlock()
                continuation.resume()
                return
            }
            flowWaiters[id] = continuation
            flowLock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resumeFlowWaiters(only: id)
            }
        }
    }

    /// Ends the current stream. The mic itself stays open for `linger`, dropping its audio, then closes. Safe on the main thread. From any other thread it hops to the main queue without waiting, so it cannot deadlock a thread that the main queue needs.
    func stop() {
        if Thread.isMainThread {
            release()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.release()
            }
        }
    }

    /// Ends the current stream and returns once no more chunks reach it.
    func stopAndWait() async {
        await MainActor.run {
            release()
        }
    }

    private func release() {
        finishStream()
        guard engine.isRunning, tapInstalled else {
            closeEngine()
            return
        }
        lingerClose?.cancel()
        let close = DispatchWorkItem { [weak self] in
            self?.closeEngine()
        }
        lingerClose = close
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: close)
    }

    /// A new stream on the mic that is still open from the last dictation, unless it closed or the chosen mic changed.
    private func reuseOpenMic() -> AsyncStream<AudioChunk>? {
        guard lingerClose != nil, engine.isRunning, tapInstalled, converter != nil,
              InputDevices.resolvedInputID().map({ $0 == inputDeviceID }) ?? true else { return nil }
        lingerClose?.cancel()
        lingerClose = nil
        finishStream()
        DictateLog.audio.info("Microphone \(self.inputDeviceID.map(String.init) ?? "default", privacy: .public): reused, still open")
        return AsyncStream<AudioChunk> { continuation in
            self.continuation = continuation
        }
    }

    private func finishStream() {
        let continuation = continuation
        self.continuation = nil
        continuation?.finish()
    }

    private func openEngine() throws -> AsyncStream<AudioChunk> {
        closeEngine()
        selectInputDevice()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        DictateLog.audio.info(
            "Microphone \(self.inputDeviceID.map(String.init) ?? "default", privacy: .public): \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels"
        )
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw InworldSTTError.audioFormatUnavailable
        }
        guard let targetFormat = PCMConversion.targetFormat(),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw InworldSTTError.audioFormatUnavailable
        }

        self.targetFormat = targetFormat
        self.converter = converter

        let stream = AsyncStream<AudioChunk> { continuation in
            self.continuation = continuation
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.setFlowing(true)
            // Between dictations the mic only lingers. Its audio goes nowhere.
            guard self.continuation != nil else { return }
            self.publishLevel(buffer)
            guard let data = self.convert(buffer) else { return }
            let seconds = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
            self.continuation?.yield(AudioChunk(time: CFAbsoluteTimeGetCurrent() - seconds, data: data))
        }
        tapInstalled = true

        addCycleNotify()
        do {
            engine.prepare()
            try engine.start()
        } catch {
            closeEngine()
            throw error
        }
        return stream
    }

    /// Points the engine at the chosen microphone. The engine is reused, so the system default is also set explicitly.
    private func selectInputDevice() {
        guard let wanted = InputDevices.resolvedInputID(), wanted != inputDeviceID,
              let unit = engine.inputNode.audioUnit else { return }
        var id = wanted
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { return }
        inputDeviceID = wanted
        engine.reset()
    }

    /// Flips the flowing flag. Turning it on or off releases anyone waiting, so a closed mic never leaves a waiter hanging.
    private func setFlowing(_ value: Bool) {
        flowLock.lock()
        guard flowing != value || !flowWaiters.isEmpty else {
            flowLock.unlock()
            return
        }
        flowing = value
        let waiters = flowWaiters.values
        flowWaiters.removeAll()
        flowLock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func resumeFlowWaiters(only id: UUID) {
        flowLock.lock()
        let waiter = flowWaiters.removeValue(forKey: id)
        flowLock.unlock()
        waiter?.resume()
    }

    /// Watches the input unit's render cycles. The first one marks the hardware as running, well before a tap buffer fills.
    private func addCycleNotify() {
        guard let unit = engine.inputNode.audioUnit else { return }
        cycleSeen = false
        if AudioUnitAddRenderNotify(unit, firstCycleNotify, Unmanaged.passUnretained(self).toOpaque()) == noErr {
            cycleNotifyUnit = unit
        }
    }

    /// Called on the audio thread. Takes the lock only once per session.
    fileprivate func noteCycle() {
        guard !cycleSeen else { return }
        cycleSeen = true
        setFlowing(true)
    }

    private func closeEngine() {
        lingerClose?.cancel()
        lingerClose = nil
        if let unit = cycleNotifyUnit {
            AudioUnitRemoveRenderNotify(unit, firstCycleNotify, Unmanaged.passUnretained(self).toOpaque())
            cycleNotifyUnit = nil
        }
        setFlowing(false)
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter = nil
        targetFormat = nil
        finishStream()
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

/// Render notify on the input unit. Only the post-render call counts: by then the hardware has delivered a cycle.
private let firstCycleNotify: AURenderCallback = { refCon, flags, _, _, _, _ in
    guard flags.pointee.contains(.unitRenderAction_PostRender) else { return noErr }
    Unmanaged<AudioRecorder>.fromOpaque(refCon).takeUnretainedValue().noteCycle()
    return noErr
}
