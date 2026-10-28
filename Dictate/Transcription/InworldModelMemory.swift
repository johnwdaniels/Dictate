import CryptoKit
import Foundation
import os

/// Preview is preferred. A key that cannot use it falls back to STT 1.
/// The choice is remembered per key so the next dictation does not probe again.
enum InworldModelMemory {
    static let preview = "inworld/inworld-stt-1-preview"
    static let standard = "inworld/inworld-stt-1"
    static let models = [preview, standard]

    private static let defaultsKey = "dictation.sttModel"
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String?]())

    static func order(for apiKey: String) -> [String] {
        guard let saved = remembered(for: apiKey) else { return models }
        return [saved] + models.filter { $0 != saved }
    }

    static func remembered(for apiKey: String) -> String? {
        let key = storageKey(for: apiKey)
        if let cached = cache.withLock({ $0[key] }) {
            return cached
        }
        let stored = UserDefaults.standard.string(forKey: key)
        let model = stored.flatMap { models.contains($0) ? $0 : nil }
        cache.withLock { $0[key] = model }
        return model
    }

    /// The dictation task calls this off the main thread. `UserDefaults` posts its change notification on the calling thread and waits for main-queue observers, which deadlocks the hotkey callback. The in-memory value is updated immediately. The defaults write happens on the main queue and only when the value changed.
    static func remember(_ model: String, for apiKey: String) {
        guard models.contains(model) else { return }
        let key = storageKey(for: apiKey)
        let changed = cache.withLock { state -> Bool in
            if (state[key] ?? nil) == model { return false }
            state[key] = model
            return true
        }
        guard changed else { return }
        writeOnMain {
            UserDefaults.standard.set(model, forKey: key)
        }
    }

    static func forget(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = storageKey(for: trimmed)
        cache.withLock { $0[key] = nil }
        writeOnMain {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func writeOnMain(_ write: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            write()
        } else {
            DispatchQueue.main.async(execute: write)
        }
    }

    private static func storageKey(for apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(defaultsKey).\(hex.prefix(16))"
    }
}
