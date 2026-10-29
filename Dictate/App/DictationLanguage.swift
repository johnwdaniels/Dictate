import Foundation

/// Language hint sent to Inworld. An empty choice means auto-detect, and the field is omitted. With no choice saved yet,
/// it is English.
enum DictationLanguage {
    static let storageKey = "dictation.language"
    static let defaultCode = "en"

    /// Codes from Inworld's Language Support page for `inworld/inworld-stt-1-preview`.
    static let options: [(name: String, code: String)] = [
        ("Arabic", "ar"),
        ("Cantonese", "yue"),
        ("Chinese", "zh"),
        ("Czech", "cs"),
        ("Danish", "da"),
        ("Dutch", "nl"),
        ("English", "en"),
        ("Filipino", "fil"),
        ("Finnish", "fi"),
        ("French", "fr"),
        ("German", "de"),
        ("Greek", "el"),
        ("Hindi", "hi"),
        ("Hungarian", "hu"),
        ("Indonesian", "id"),
        ("Italian", "it"),
        ("Japanese", "ja"),
        ("Korean", "ko"),
        ("Macedonian", "mk"),
        ("Malay", "ms"),
        ("Persian", "fa"),
        ("Polish", "pl"),
        ("Portuguese", "pt"),
        ("Romanian", "ro"),
        ("Russian", "ru"),
        ("Spanish", "es"),
        ("Swedish", "sv"),
        ("Thai", "th"),
        ("Turkish", "tr"),
        ("Vietnamese", "vi"),
    ]

    static var storedCode: String? {
        let raw = (UserDefaults.standard.string(forKey: storageKey) ?? defaultCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.caseInsensitiveCompare("auto") != .orderedSame else { return nil }
        guard options.contains(where: { $0.code == raw }) else { return nil }
        return raw
    }
}
