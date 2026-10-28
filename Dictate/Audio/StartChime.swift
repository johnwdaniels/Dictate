import AppKit
import Foundation

/// The sound played when transcription starts. Off sends audio as soon as the session is ready.
enum StartSound: String, CaseIterable, Identifiable {
    case off
    case ding
    case boop
    case pop
    case chime
    case tap

    static let storageKey = "dictation.startSound"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .ding: "Ding"
        case .boop: "Boop"
        case .pop: "Pop"
        case .chime: "Chime"
        case .tap: "Tap"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .off: 0
        case .ding: 0.26
        case .boop: 0.20
        case .pop: 0.08
        case .chime: 0.32
        case .tap: 0.10
        }
    }

    static var current: StartSound {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? StartSound.ding.rawValue
        return StartSound(rawValue: raw) ?? .ding
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
        let sound = NSSound(data: Tone.wav(for: choice))
        cache[choice] = sound
        return sound
    }
}

private enum Tone {
    static let sampleRate = 44_100

    static func wav(for choice: StartSound) -> Data {
        switch choice {
        case .off:
            return Data()
        case .ding:
            return render(seconds: choice.duration, ding)
        case .boop:
            return render(seconds: choice.duration, boop)
        case .pop:
            return render(seconds: choice.duration, pop)
        case .chime:
            return render(seconds: choice.duration, chime)
        case .tap:
            return render(seconds: choice.duration, tap)
        }
    }

    /// A small bell: one bright strike, then a very short ring.
    private static func ding(_ time: Double) -> Double {
        let carrier = 1_568.0
        let strike = sin(2 * Double.pi * carrier * 2.76 * time) * exp(-28 * time)
        var sample = sin(2 * Double.pi * carrier * time + 2.4 * strike) * exp(-14 * time)
        sample += 0.12 * sin(2 * Double.pi * carrier * 0.5 * time) * exp(-10 * time)
        return sample * attack(time, seconds: 0.002) * 0.22
    }

    /// A soft low bubble.
    private static func boop(_ time: Double) -> Double {
        let frequency = 280.0 - 50.0 * min(time, 0.2)
        return sin(2 * Double.pi * frequency * time) * exp(-11 * time) * attack(time, seconds: 0.006) * 0.28
    }

    /// A tiny mid click.
    private static func pop(_ time: Double) -> Double {
        sin(2 * Double.pi * 740 * time) * exp(-48 * time) * attack(time, seconds: 0.001) * 0.2
    }

    /// Two quiet notes, a fourth apart.
    private static func chime(_ time: Double) -> Double {
        note(time, start: 0, frequency: 880) + note(time, start: 0.12, frequency: 1_174)
    }

    /// A short dull knock.
    private static func tap(_ time: Double) -> Double {
        let knock = sin(2 * Double.pi * 180 * time) * exp(-32 * time)
        let tick = sin(2 * Double.pi * 980 * time) * exp(-70 * time)
        return (knock * 0.7 + tick * 0.18) * attack(time, seconds: 0.001) * 0.3
    }

    private static func note(_ time: Double, start: Double, frequency: Double) -> Double {
        let local = time - start
        guard local >= 0 else { return 0 }
        let strike = sin(2 * Double.pi * frequency * 2.4 * local) * exp(-30 * local)
        return sin(2 * Double.pi * frequency * local + 1.6 * strike) * exp(-16 * local) * 0.16
    }

    private static func attack(_ time: Double, seconds: Double) -> Double {
        min(1, time / seconds)
    }

    private static func render(seconds: TimeInterval, _ sample: (Double) -> Double) -> Data {
        let count = Int(seconds * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            let clamped = max(-1, min(1, sample(time)))
            samples[index] = Int16(clamped * 32_767)
        }
        return wavData(samples: samples)
    }

    private static func wavData(samples: [Int16]) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * 2))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLE(UInt32(dataSize))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
