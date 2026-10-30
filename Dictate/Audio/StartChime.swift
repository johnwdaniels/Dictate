import AppKit
import Foundation

/// The sound played when transcription starts. Off sends audio as soon as the session is ready.
/// Each sound is a short WAV in Audio/StartSounds, named after its raw value.
enum StartSound: String, CaseIterable, Identifiable {
    case off
    case softLift
    case dot
    case doubleDot
    case dotArpeggio
    case bubble
    case kalimba
    case woodKnock
    case bwip
    case droidChirp
    case retroBlip
    case oo
    case swell
    case spinUp
    case ringBlip
    case marblePop

    static let storageKey = "dictation.startSound"
    static let fallback = StartSound.softLift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .softLift: "Cheryl Approved"
        case .dot: "Per Slack"
        case .doubleDot: "Circle Back"
        case .dotArpeggio: "Danil o'Clock"
        case .bubble: "Pricing Sheet"
        case .kalimba: "Nine Hundred Eleven"
        case .woodKnock: "Talk to Brian"
        case .bwip: "Rebase First"
        case .droidChirp: "Karim Mode"
        case .retroBlip: "Gate 1"
        case .oo: "Ask Sage"
        case .swell: "Kylan Cinema"
        case .spinUp: "John's Build"
        case .ringBlip: "HubSpot Says"
        case .marblePop: "Pedro PR"
        }
    }

    /// Length of the bundled file. Audio is held back until the sound ends, so the mic doesn't catch it.
    var duration: TimeInterval {
        switch self {
        case .off: 0
        case .softLift: 0.208
        case .dot: 0.199
        case .doubleDot: 0.284
        case .dotArpeggio: 0.320
        case .bubble: 0.179
        case .kalimba: 0.250
        case .woodKnock: 0.112
        case .bwip: 0.299
        case .droidChirp: 0.249
        case .retroBlip: 0.270
        case .oo: 0.296
        case .swell: 0.237
        case .spinUp: 0.199
        case .ringBlip: 0.244
        case .marblePop: 0.200
        }
    }

    /// Bundled WAV for this sound. Nil for Off.
    var fileURL: URL? {
        guard self != .off else { return nil }
        return Bundle.main.url(forResource: rawValue, withExtension: "wav")
    }

    /// Choices saved by older versions (ding, boop, pop, chime, tap) fall back to Cheryl Approved.
    static var current: StartSound {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? fallback.rawValue
        return StartSound(rawValue: raw) ?? fallback
    }

    /// Rewrites a saved sound that no longer exists, so the Settings picker shows the sound that actually plays.
    static func retireOldChoice(in defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: storageKey), StartSound(rawValue: raw) == nil else { return }
        defaults.set(fallback.rawValue, forKey: storageKey)
    }
}

enum StartChime {
    private static var playing: NSSound?
    private static var cache: [StartSound: NSSound] = [:]

    /// How long the selected sound rings. Callers wait this long before sending microphone audio.
    static var ringDuration: TimeInterval { StartSound.current.duration }
    static func play() {
        let choice = StartSound.current
        guard choice != .off, let sound = cached(choice) else { return }
        sound.stop()
        sound.currentTime = 0
        sound.volume = 0.35
        playing = sound
        sound.play()
    }

    private static func cached(_ choice: StartSound) -> NSSound? {
        if let sound = cache[choice] { return sound }
        guard let url = choice.fileURL, let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
        cache[choice] = sound
        return sound
    }
}
