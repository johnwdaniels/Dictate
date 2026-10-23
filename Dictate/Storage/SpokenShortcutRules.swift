import Foundation

enum SpokenShortcutRules {
    struct Idea: Identifiable {
        var id: String { phrase }
        var title: String
        var phrase: String
    }

    static let ideas = [
        Idea(title: "Email address", phrase: "my email"),
        Idea(title: "Phone number", phrase: "my phone number"),
        Idea(title: "Home address", phrase: "my address"),
        Idea(title: "Signature", phrase: "my signature"),
    ]

    static func issue(for phrase: String, expansion: String, existing: [String]) -> String? {
        let spoken = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return nil }
        if expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add the text that should be inserted."
        }
        if existing.contains(where: { DictionaryTermRules.matches($0, spoken) }) {
            return "That phrase is already a shortcut."
        }
        return nil
    }

    static func canAdd(phrase: String, expansion: String, existing: [String]) -> Bool {
        let spoken = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return !spoken.isEmpty && issue(for: phrase, expansion: expansion, existing: existing) == nil
    }
}
