import Foundation

enum DictionaryTermRules {
    static let maximum = 100

    /// Letters and digits in any script, spaces, and the punctuation Inworld accepts.
    /// A straight double quote is not allowed, so cleaning turns curly quotes into an apostrophe.
    private static let punctuation: Set<Character> = [".", ",", "'", "(", ")", ":", "!", "?", ";", "-"]

    static func issue(for draft: String, existing: [String], count: Int) -> String? {
        let term = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        if let character = firstDisallowed(in: term) {
            return "\(name(of: character)) isn't allowed."
        }
        if count >= maximum {
            return "The dictionary already has \(maximum) terms."
        }
        if existing.contains(where: { matches($0, term) }) {
            return "That term is already in the dictionary."
        }
        return nil
    }

    static func canAdd(_ draft: String, existing: [String], count: Int) -> Bool {
        let term = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !term.isEmpty && issue(for: draft, existing: existing, count: count) == nil
    }

    /// A button title when the draft contains a curly quote or underscore that can be rewritten.
    /// Inworld rejects `"` and curly quotes, so quotes become a straight apostrophe.
    static func cleanTitle(for draft: String) -> String? {
        let quotes = draft.contains { "“”‘’".contains($0) }
        let underscore = draft.contains("_")
        switch (quotes, underscore) {
        case (true, true):
            return "Replace “ ” with ' and _ with a space"
        case (true, false):
            return "Replace “ ” with '"
        case (false, true):
            return "Replace _ with a space"
        case (false, false):
            return nil
        }
    }

    static func cleaned(_ draft: String) -> String {
        var text = draft
        for quote in ["“", "”", "‘", "’"] {
            text = text.replacingOccurrences(of: quote, with: "'")
        }
        text = text.replacingOccurrences(of: "_", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text
    }

    static func planImport(text: String, existing: [String]) -> DictionaryImportPlan {
        var seen = existing
        var accepted: [String] = []
        var skipped: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for (offset, raw) in lines.enumerated() {
            let lineNumber = offset + 1
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { continue }
            if let character = firstDisallowed(in: term) {
                skipped.append("Line \(lineNumber): \(name(of: character)) isn't allowed.")
                continue
            }
            if seen.contains(where: { matches($0, term) }) {
                skipped.append("Line \(lineNumber): \(term) is already in the dictionary.")
                continue
            }
            if seen.count >= maximum {
                skipped.append("Line \(lineNumber): the dictionary already has \(maximum) terms.")
                continue
            }
            accepted.append(term)
            seen.append(term)
        }
        return DictionaryImportPlan(accepted: accepted, skipped: skipped)
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// Whether Inworld accepts every character of the term as a prompt.
    static func isAllowed(_ term: String) -> Bool {
        firstDisallowed(in: term) == nil
    }

    private static func firstDisallowed(in term: String) -> Character? {
        term.first { !isAllowed($0) }
    }

    private static func isAllowed(_ character: Character) -> Bool {
        if character == " " || punctuation.contains(character) { return true }
        if character.isLetter { return true }
        return character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .decimalNumber }
    }

    private static func name(of character: Character) -> String {
        if character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) {
            return "a control character"
        }
        return String(character)
    }
}

struct DictionaryImportPlan {
    var accepted: [String]
    var skipped: [String]

    var summary: String {
        if accepted.isEmpty && skipped.isEmpty {
            return "That file has no terms."
        }
        var lines: [String] = []
        if accepted.count == 1 {
            lines.append("Added 1 term.")
        } else if !accepted.isEmpty {
            lines.append("Added \(accepted.count) terms.")
        }
        let shown = skipped.prefix(8)
        lines.append(contentsOf: shown)
        let remaining = skipped.count - shown.count
        if remaining > 0 {
            lines.append("And \(remaining) more.")
        }
        return lines.joined(separator: "\n")
    }
}

enum DictionaryReplacements {
    static func issue(for find: String, existing: [String]) -> String? {
        let trimmed = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if existing.contains(where: { DictionaryTermRules.matches($0, trimmed) }) {
            return "That replacement is already in the list."
        }
        return nil
    }

    static func canAdd(find: String, existing: [String]) -> Bool {
        let trimmed = find.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && issue(for: find, existing: existing) == nil
    }

    /// Case-insensitive, longest match first, and only where the find text is not inside a longer word.
    /// Every match is replaced once, so a shorter rule does not rewrite the text a longer rule just inserted.
    static func apply(_ rules: [(find: String, replacement: String)], to text: String) -> String {
        let ordered = rules
            .map { (find: $0.find.trimmingCharacters(in: .whitespacesAndNewlines), replacement: $0.replacement) }
            .filter { !$0.find.isEmpty }
            .sorted { $0.find.count > $1.find.count }
        guard !ordered.isEmpty else { return text }
        let pattern = ordered.map { rule in
            "(?<![\\p{L}\\p{N}])(?:" + NSRegularExpression.escapedPattern(for: rule.find) + ")(?![\\p{L}\\p{N}])"
        }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let found = String(result[range])
            guard let rule = ordered.first(where: { DictionaryTermRules.matches($0.find, found) }) else { continue }
            result.replaceSubrange(range, with: rule.replacement)
        }
        return result
    }
}
