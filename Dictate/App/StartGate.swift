import Foundation

/// Decides which recorded audio a dictation sends.
///
/// The microphone opens the moment the shortcut is pressed and every chunk is kept. The gate opens when the start cue
/// plays. Audio from before the cue ends is skipped, so the start sound is never transcribed, and audio after it is sent
/// even if the connection to Inworld is still opening.
final class StartGate: @unchecked Sendable {
    enum State: Equatable {
        case waiting
        case open
        case cancelled
    }

    /// The quiet after the start sound, so its tail is not transcribed either.
    static let soundTail: TimeInterval = 0.08

    private let lock = NSLock()
    private let keepFrom: CFAbsoluteTime?
    private var currentState = State.waiting
    private var currentForwardFrom = CFAbsoluteTime.infinity

    /// `keepFrom` is the key-down time of a right-side modifier, when the mic starts before the press is confirmed.
    init(keepFrom: CFAbsoluteTime? = nil) {
        self.keepFrom = keepFrom
    }

    /// The first moment of audio to send. With a start sound, the end of the sound. Without one, everything from the
    /// key-down, or from when the mic opened.
    static func forwardStart(cue: CFAbsoluteTime, ring: TimeInterval, keepFrom: CFAbsoluteTime?) -> CFAbsoluteTime {
        if ring > 0 {
            return cue + ring + soundTail
        }
        return keepFrom ?? 0
    }

    var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    var forwardFrom: CFAbsoluteTime {
        lock.lock()
        defer { lock.unlock() }
        return currentForwardFrom
    }

    func open(cue: CFAbsoluteTime, ring: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard currentState == .waiting else { return }
        currentForwardFrom = Self.forwardStart(cue: cue, ring: ring, keepFrom: keepFrom)
        currentState = .open
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard currentState == .waiting else { return }
        currentState = .cancelled
    }
}
