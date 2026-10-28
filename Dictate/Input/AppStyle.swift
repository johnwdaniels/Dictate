import Foundation

/// How formal a transcript reads once it is pasted.
enum WritingStyle: String, CaseIterable, Identifiable {
    case veryCasual
    case casual
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryCasual: "Very casual"
        case .casual: "Casual"
        case .professional: "Professional"
        }
    }
}

/// Groups of apps that share a style. An app not in any list falls under Other apps.
enum AppCategory: String, CaseIterable, Identifiable {
    case personal
    case work
    case email
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Emails"
        case .other: "Other apps"
        }
    }

    var defaultStyle: WritingStyle {
        switch self {
        case .personal, .work: .casual
        case .email, .other: .professional
        }
    }

    var defaultBundleIDs: [String] {
        switch self {
        case .personal:
            ["com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.facebook.archon", "ru.keepcoder.Telegram", "org.whispersystems.signal-desktop", "com.hnc.Discord"]
        case .work:
            ["com.tinyspeck.slackmacgap", "com.microsoft.teams2"]
        case .email:
            ["com.apple.mail", "com.superhuman.electron", "com.microsoft.Outlook"]
        case .other:
            []
        }
    }

    var styleKey: String { "style.\(rawValue)" }
    var appsKey: String { "style.\(rawValue).apps" }
}

enum AppStyle {
    static let sample = "Hey, are you free tomorrow? Let's grab lunch."

    /// Names for default apps that may not be installed.
    static let knownNames = [
        "com.apple.MobileSMS": "Messages",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.facebook.archon": "Messenger",
        "ru.keepcoder.Telegram": "Telegram",
        "org.whispersystems.signal-desktop": "Signal",
        "com.hnc.Discord": "Discord",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.microsoft.teams2": "Teams",
        "com.apple.mail": "Mail",
        "com.superhuman.electron": "Superhuman",
        "com.microsoft.Outlook": "Outlook",
    ]

    static func style(for category: AppCategory, in defaults: UserDefaults = .standard) -> WritingStyle {
        defaults.string(forKey: category.styleKey).flatMap(WritingStyle.init(rawValue:)) ?? category.defaultStyle
    }

    static func bundleIDs(for category: AppCategory, in defaults: UserDefaults = .standard) -> [String] {
        guard category != .other else { return [] }
        return defaults.stringArray(forKey: category.appsKey) ?? category.defaultBundleIDs
    }

    static func category(for bundleID: String, in defaults: UserDefaults = .standard) -> AppCategory {
        AppCategory.allCases.first { bundleIDs(for: $0, in: defaults).contains(bundleID) } ?? .other
    }

    /// Puts an app in one category and takes it out of the others.
    static func move(_ bundleID: String, to category: AppCategory, in defaults: UserDefaults = .standard) {
        for other in AppCategory.allCases where other != .other {
            var ids = bundleIDs(for: other, in: defaults).filter { $0 != bundleID }
            if other == category { ids.append(bundleID) }
            defaults.set(ids, forKey: other.appsKey)
        }
    }

    static func remove(_ bundleID: String, from category: AppCategory, in defaults: UserDefaults = .standard) {
        defaults.set(bundleIDs(for: category, in: defaults).filter { $0 != bundleID }, forKey: category.appsKey)
    }

    static func styled(_ transcript: String, bundleID: String, in defaults: UserDefaults = .standard) -> String {
        apply(style(for: category(for: bundleID, in: defaults), in: defaults), to: transcript)
    }

    static func apply(_ style: WritingStyle, to transcript: String) -> String {
        switch style {
        case .professional: transcript
        case .casual: droppingFinalPeriod(transcript)
        case .veryCasual: lowercasingSentenceStarts(droppingFinalPeriod(transcript))
        }
    }

    /// Question marks, exclamation marks and ellipses stay, since they change the meaning.
    static func droppingFinalPeriod(_ transcript: String) -> String {
        guard transcript.count > 1, transcript.hasSuffix("."), !transcript.hasSuffix("..") else { return transcript }
        return String(transcript.dropLast())
    }

    /// Lowercases the first word of each sentence. "I" and acronyms such as "NASA" stay as they are.
    static func lowercasingSentenceStarts(_ transcript: String) -> String {
        var atSentenceStart = true
        let words = transcript.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            var word = String(word)
            if atSentenceStart, !word.isEmpty, !keepsCapital(word) {
                word = word.prefix(1).lowercased() + word.dropFirst()
            }
            if !word.isEmpty {
                let end = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)"))
                atSentenceStart = end.hasSuffix(".") || end.hasSuffix("?") || end.hasSuffix("!")
            }
            return word
        }
        return words.joined(separator: " ")
    }

    private static func keepsCapital(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        if letters == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return true }
        return letters.count > 1 && letters == letters.uppercased()
    }
}
