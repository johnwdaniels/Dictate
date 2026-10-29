import Foundation

/// Local clean-up applied to a transcript before replacements and style. Nothing here leaves the Mac.
enum TranscriptCleanup {
    static let removeFillersKey = "cleanup.removeFillers"
    static let formatNumbersKey = "cleanup.formatNumbers"

    /// Missing key means on, matching the Settings toggle's default.
    static var removeFillers: Bool {
        guard UserDefaults.standard.object(forKey: removeFillersKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: removeFillersKey)
    }

    /// Missing key means on, matching the Settings toggle's default.
    static var formatNumbers: Bool {
        guard UserDefaults.standard.object(forKey: formatNumbersKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: formatNumbersKey)
    }

    static func clean(
        _ transcript: String,
        removeFillers: Bool = removeFillers,
        formatNumbers: Bool = formatNumbers,
        language: String? = DictationLanguage.storedCode
    ) -> String {
        // Noise, not a filler someone might want to keep, so this ignores the switches.
        var text = removingStrayCJK(transcript, language: language)
        text = removingStrayLetter(text, language: language)
        if removeFillers { text = removingFillers(text) }
        if formatNumbers { text = formattingNumbers(text) }
        return text
    }

    // MARK: Stray characters

    private static let cjkLanguages: Set<String> = ["zh", "ja", "ko", "yue"]
    private static let cjk = #"[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]"#

    /// Drops a one- or two-character Chinese, Japanese or Korean token at the start or end of a dictation that is otherwise in Latin script.
    ///
    /// The model sometimes writes a hesitation before the first word as 嗯, the Chinese "mm", even with English chosen.
    /// It is left alone when the dictation language is Chinese, Japanese or Korean, or when the text has no Latin letters.
    static func removingStrayCJK(_ transcript: String, language: String?) -> String {
        if let language, cjkLanguages.contains(language.lowercased().components(separatedBy: "-").first ?? "") {
            return transcript
        }
        guard transcript.range(of: #"\p{Latin}"#, options: .regularExpression) != nil,
              transcript.range(of: cjk, options: .regularExpression) != nil else { return transcript }
        // Only at the very start or end, where a hesitation lands. A word said on purpose mid-sentence stays.
        let leading = #"^\s*"# + cjk + #"{1,2}[。、，！？…,.!?]*(\s+|(?=\p{Latin}))"#
        let trailing = #"\s+"# + cjk + #"{1,2}[。、，！？…,.!?]*\s*$"#
        var text = replace(leading, in: transcript, with: "")
        text = replace(trailing, in: text, with: "")
        text = text.trimmingCharacters(in: .whitespaces)
        // A dictation that started with the stray token now starts with the next word.
        let startedWithIt = transcript.range(of: "^" + cjk, options: .regularExpression) != nil
        guard startedWithIt, let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Drops a lone letter with a period at the start of an English dictation, such as "É." from a hesitation before
    /// the first word. "I" and "A" are words, so they stay. Runs only for English or auto-detect, and only when the rest
    /// is plain ASCII, so a Portuguese "É." (it is) is kept.
    static func removingStrayLetter(_ transcript: String, language: String?) -> String {
        if let language, !language.lowercased().hasPrefix("en") { return transcript }
        let pattern = #"^\s*([\p{L}])[.!?…。]+\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)),
              let letterRange = Range(match.range(at: 1), in: transcript),
              let whole = Range(match.range, in: transcript) else { return transcript }
        let letter = transcript[letterRange].uppercased()
        guard letter != "I", letter != "A" else { return transcript }
        let rest = String(transcript[whole.upperBound...])
        guard !rest.isEmpty, rest.unicodeScalars.allSatisfy(\.isASCII), rest.contains(where: \.isLetter) else { return transcript }
        return rest
    }

    // MARK: Fillers

    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "eh", "hm", "hmm", "mm"]

    /// Drops "um" and similar sounds, and "you know" only when commas set it off, so "everything you know" stays.
    static func removingFillers(_ transcript: String) -> String {
        var text = transcript
        text = replace(#",\s+you know([.?!])"#, in: text, with: "$1")
        text = replace(#",\s+you know,"#, in: text, with: "")

        var tokens = Token.split(text)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let atSentenceStart = index == 0 || tokens[index - 1].endsSentence
            var removed = 0
            if token.lead.isEmpty, fillers.contains(token.core.lowercased()) {
                removed = 1
            } else if atSentenceStart, token.lead.isEmpty, token.trail.isEmpty, token.core.lowercased() == "you",
                      index + 1 < tokens.count, tokens[index + 1].core.lowercased() == "know", tokens[index + 1].trail == "," {
                removed = 2
            }
            guard removed > 0 else {
                index += 1
                continue
            }
            let lastRemoved = tokens[index + removed - 1]
            if let end = lastRemoved.trail.last, ".?!".contains(end), index > 0, tokens[index - 1].trail.isEmpty {
                tokens[index - 1].trail = String(end)
            }
            tokens.removeSubrange(index..<(index + removed))
            // A sentence that started with the filler now starts with the next word.
            if atSentenceStart, index < tokens.count {
                tokens[index].core = tokens[index].core.prefix(1).uppercased() + tokens[index].core.dropFirst()
            }
        }
        return tokens.map(\.text).joined(separator: " ")
    }

    // MARK: Numbers

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]

    /// Writes spoken numbers as digits: "ninety days" becomes "90 days", "fifty percent" becomes "50%", "twenty twenty" becomes "2020".
    /// One to nine stay as words unless a unit such as percent follows, so "one of them" is unchanged.
    static func formattingNumbers(_ transcript: String) -> String {
        let tokens = Token.split(transcript)
        var output: [Token] = []
        var index = 0
        while index < tokens.count {
            // A capitalized number word mid-sentence is part of a name, such as Eleven Labs.
            let first = tokens[index].core.first
            if index > 0, !tokens[index - 1].endsSentence, first?.isUppercase == true {
                output.append(tokens[index])
                index += 1
            } else if let year = year(in: tokens, at: index) {
                output.append(year.token)
                index = year.end
            } else if let number = number(in: tokens, at: index) {
                output.append(number.token)
                index = number.end
            } else if let digits = digits(in: tokens, at: index) {
                output.append(digits.token)
                index = digits.end
            } else {
                output.append(tokens[index])
                index += 1
            }
        }
        return output.map(\.text).joined(separator: " ")
    }

    private enum Part {
        case unit(Int)
        case ten(Int)
        case hundred
        case scale(Int)
    }

    private static func parts(_ core: String) -> [Part]? {
        let words = core.lowercased().split(separator: "-").map(String.init)
        guard !words.isEmpty else { return nil }
        var result: [Part] = []
        for word in words {
            if let value = units[word] {
                result.append(.unit(value))
            } else if let value = tens[word] {
                result.append(.ten(value))
            } else if word == "hundred" {
                result.append(.hundred)
            } else if let value = scales[word] {
                result.append(.scale(value))
            } else {
                return nil
            }
        }
        return result
    }

    /// Running total for a spoken number. `apply` refuses a word that cannot follow, such as "two three".
    private static func isUnitOrTen(_ part: Part?) -> Bool {
        switch part {
        case .unit, .ten: true
        default: false
        }
    }

    private struct Accumulator {
        var total = 0
        var current = 0
        var last: Part?
        var words = 0
        var hasMultiplier = false

        var value: Int { total + current }

        mutating func apply(_ part: Part) -> Bool {
            switch part {
            case .unit(let value):
                switch last {
                case .unit: return false
                case .ten where value >= 10: return false
                default: current += value
                }
            case .ten(let value):
                switch last {
                case .unit, .ten: return false
                default: current += value
                }
            case .hundred:
                // "Five hundred", and also "nineteen hundred" or "twenty five hundred".
                guard (1...99).contains(current), TranscriptCleanup.isUnitOrTen(last) else { return false }
                current *= 100
                hasMultiplier = true
            case .scale(let value):
                guard current > 0 else { return false }
                total += current * value
                current = 0
                hasMultiplier = true
            }
            last = part
            words += 1
            return true
        }
    }

    private static func number(in tokens: [Token], at start: Int) -> (token: Token, end: Int)? {
        var accumulator = Accumulator()
        var index = start
        var lastConsumed = start
        while index < tokens.count {
            let token = tokens[index]
            if index > start, !token.lead.isEmpty { break }
            let word = token.core.lowercased()
            let next = index + 1 < tokens.count ? tokens[index + 1].core.lowercased() : ""

            if (word == "a" || word == "an"), index == start, token.trail.isEmpty, next == "hundred" || next == "thousand" {
                accumulator.current = 1
                accumulator.last = .unit(1)
                index += 1
                continue
            }
            if word == "and", accumulator.hasMultiplier, token.trail.isEmpty, isUnitOrTen(parts(next)?.first) {
                index += 1
                continue
            }
            guard let parts = parts(token.core) else { break }
            var trial = accumulator
            guard parts.allSatisfy({ trial.apply($0) }) else { break }
            accumulator = trial
            lastConsumed = index
            index += 1
            if !token.trail.isEmpty { break }
        }
        guard accumulator.words > 0 else { return nil }

        let phrase = Array(tokens[start...lastConsumed])
        let value = accumulator.value
        let lastWord = phrase.last!.core.lowercased()
        let following = lastConsumed + 1 < tokens.count && phrase.last!.trail.isEmpty ? tokens[lastConsumed + 1] : nil
        let unit = following.map { $0.core.lowercased() }
        let isUnit = unit == "percent" || unit == "dollars" || unit == "dollar"
        if accumulator.words == 1, value < 10, !isUnit, scales[lastWord] == nil { return nil }

        var digits: String
        if let scale = scales[lastWord], scale >= 1_000_000, value % scale == 0 {
            digits = grouped(value / scale) + " " + lastWord
        } else {
            let saidThousand = phrase.contains { $0.core.lowercased().contains("thousand") }
            digits = saidThousand || value >= 10_000 ? grouped(value) : String(value)
        }
        var token = Token(lead: phrase.first!.lead, core: digits, trail: phrase.last!.trail)
        var end = lastConsumed + 1
        if isUnit, let following, !digits.contains(" ") {
            token = unitToken(token, unit: unit!, following: following)
            end += 1
        }
        return (token, end)
    }

    /// "Nineteen ninety nine" and "twenty twenty-six" are years.
    private static func year(in tokens: [Token], at start: Int) -> (token: Token, end: Int)? {
        guard start + 1 < tokens.count else { return nil }
        let first = tokens[start]
        guard first.trail.isEmpty, let century = ["nineteen": 19, "twenty": 20][first.core.lowercased()] else { return nil }

        var index = start + 1
        var value = 0
        var last = start
        let second = tokens[index]
        guard second.lead.isEmpty, let secondParts = parts(second.core) else { return nil }
        switch secondParts.first {
        case .unit(let teen) where teen >= 10 && secondParts.count == 1:
            value = teen
        case .ten(let ten):
            value = ten
            if secondParts.count == 2, case .unit(let one) = secondParts[1], one < 10 {
                value += one
            } else if secondParts.count == 1, second.trail.isEmpty, index + 1 < tokens.count,
                      tokens[index + 1].lead.isEmpty, let one = units[tokens[index + 1].core.lowercased()], (1...9).contains(one) {
                value += one
                index += 1
            } else if secondParts.count != 1 {
                return nil
            }
        default:
            return nil
        }
        last = index
        if last + 1 < tokens.count, tokens[last].trail.isEmpty,
           ["hundred", "thousand", "million", "billion"].contains(tokens[last + 1].core.lowercased()) {
            return nil
        }
        let token = Token(lead: first.lead, core: String(century * 100 + value), trail: tokens[last].trail)
        return (token, last + 1)
    }

    /// Digits that are already written, followed by "percent" or "dollars".
    private static func digits(in tokens: [Token], at start: Int) -> (token: Token, end: Int)? {
        let token = tokens[start]
        guard token.trail.isEmpty, start + 1 < tokens.count,
              !token.core.isEmpty, token.core.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }),
              token.core.first!.isNumber else { return nil }
        let unit = tokens[start + 1].core.lowercased()
        guard unit == "percent" || unit == "dollars" || unit == "dollar" else { return nil }
        return (unitToken(token, unit: unit, following: tokens[start + 1]), start + 2)
    }

    private static func unitToken(_ token: Token, unit: String, following: Token) -> Token {
        let core = unit == "percent" ? token.core + "%" : "$" + token.core
        return Token(lead: token.lead, core: core, trail: following.trail)
    }

    /// "Nineteen hundred" stays 1900, since it is usually a year. Numbers said with "thousand" get a comma.
    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// A word with the punctuation around it, such as "(twenty," split into "(", "twenty" and ",".
private struct Token {
    var lead: String
    var core: String
    var trail: String

    var text: String { lead + core + trail }

    var endsSentence: Bool {
        guard let end = trail.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)")).last else { return false }
        return ".?!".contains(end)
    }

    static func split(_ text: String) -> [Token] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { piece in
            let word = String(piece)
            let isWordCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber }
            guard let first = word.firstIndex(where: isWordCharacter),
                  let last = word.lastIndex(where: isWordCharacter) else {
                return Token(lead: word, core: "", trail: "")
            }
            return Token(
                lead: String(word[..<first]),
                core: String(word[first...last]),
                trail: String(word[word.index(after: last)...])
            )
        }
    }
}
