import CryptoKit
import Foundation

/// Preview is preferred. A key that cannot use it falls back to STT 1.
/// The choice is remembered per key so the next dictation does not probe again.
enum InworldModelMemory {
    static let preview = "inworld/inworld-stt-1-preview"
    static let standard = "inworld/inworld-stt-1"
    static let models = [preview, standard]

    private static let defaultsKey = "dictation.sttModel"

    static func order(for apiKey: String) -> [String] {
        guard let saved = remembered(for: apiKey) else { return models }
        return [saved] + models.filter { $0 != saved }
    }

    static func remembered(for apiKey: String) -> String? {
        let stored = UserDefaults.standard.string(forKey: storageKey(for: apiKey))
        guard let stored, models.contains(stored) else { return nil }
        return stored
    }

    static func remember(_ model: String, for apiKey: String) {
        guard models.contains(model) else { return }
        UserDefaults.standard.set(model, forKey: storageKey(for: apiKey))
    }

    static func forget(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: storageKey(for: trimmed))
    }

    private static func storageKey(for apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(defaultsKey).\(hex.prefix(16))"
    }
}
