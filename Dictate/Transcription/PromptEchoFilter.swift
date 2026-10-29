import Foundation

/// Removes dictionary terms the speech model writes back on its own.
///
/// The terms go to Inworld as `prompts`, a soft bias. During silence the model can return the prompt list itself as a
/// transcript. Nothing in the app inserts the terms, so this filters what comes back.
enum PromptEchoFilter {
    /// A run this long, in the same order as the saved terms, is the prompt list, not speech.
    static let minimumOrderedRun = 3

    /// The segment to keep from one final result. Empty when the whole segment is echoed terms.
    static func filter(_ segment: String, terms: [String], isFirstSegment: Bool) -> String {
        let patterns = Pattern.make(terms)
        guard !patterns.isEmpty else { return segment }
        let unlabeled = removingHeaderedLists(segment, patterns: patterns)
        let words = Word.split(unlabeled)
        guard !words.isEmpty else { return unlabeled == segment ? segment : "" }

        let matches = match(words, patterns)
        // Every word belongs to a term. Two or more terms, or a lone term after earlier speech, is an echo.
        if let matches, matches.count >= 2 || (matches.count == 1 && !isFirstSegment) {
            return ""
        }
        return trimmingOrderedRuns(unlabeled, words: words, patterns: patterns)
    }

    // MARK: Label

    /// Inworld can echo the prompt under its own label, as in "Expected terms: Kylan, Cheryl, Inworld, T I bet".
    /// The label, the terms after it in any order and a cut-off last term are removed. Speech on either side stays.
    private static func removingHeaderedLists(_ segment: String, patterns: [Pattern]) -> String {
        var text = segment
        while let cut = headeredList(in: text, patterns: patterns) {
            let before = text[..<cut.lowerBound].trimmingCharacters(in: .whitespaces)
            let after = text[cut.upperBound...].trimmingCharacters(in: .whitespaces)
            text = before.isEmpty || after.isEmpty ? before + after : before + " " + after
        }
        return text
    }

    /// The range of the first "Expected terms:" label and the list that follows it.
    private static func headeredList(in text: String, patterns: [Pattern]) -> Range<String.Index>? {
        let words = Word.split(text)
        guard words.count >= 2 else { return nil }
        for index in 0..<(words.count - 1) where words[index].key == "expected" && words[index + 1].key == "terms" {
            let label = text[words[index + 1].range.upperBound...].drop { $0 == " " }
            guard label.first == ":" else { continue }

            var end = text.index(after: label.startIndex)
            var position = index + 2
            while position < words.count, let found = term(at: position, in: words, patterns) {
                position = found.end
                end = words[position - 1].range.upperBound
            }
            // A label with speech after it and no term, as in "Expected terms: net 30", is speech.
            guard position > index + 2 || position == words.count else { continue }
            // The model can stop mid-term. After a comma, words that only start a term are that last term.
            if position > index + 2, position < words.count,
               text[words[position - 1].range.upperBound..<words[position].range.lowerBound].contains(","),
               let length = cutOffTermLength(at: position, in: words, patterns) {
                end = words[position + length - 1].range.upperBound
            }
            let separators = text[end...].prefix { ",;:.!? ".contains($0) }
            return words[index].range.lowerBound..<separators.endIndex
        }
        return nil
    }

    /// How many words at `position` are the start of a term cut off mid-word, as "T" for "TTS" or "GTM Sa" for "GTM Sage".
    private static func cutOffTermLength(at position: Int, in words: [Word], _ patterns: [Pattern]) -> Int? {
        for pattern in patterns {
            for whole in 0..<pattern.words.count where position + whole < words.count {
                let full = words[position..<(position + whole)].map(\.key)
                let last = words[position + whole].key
                if full == Array(pattern.words[..<whole]),
                   pattern.words[whole].count > last.count, pattern.words[whole].hasPrefix(last) {
                    return whole + 1
                }
            }
        }
        return nil
    }

    // MARK: Matching

    private struct Pattern {
        let index: Int
        let words: [String]

        static func make(_ terms: [String]) -> [Pattern] {
            terms.enumerated().compactMap { index, term in
                let words = Word.split(term).map(\.key)
                return words.isEmpty ? nil : Pattern(index: index, words: words)
            }
            // Longest first, so "GTM Sage" wins over "Sage".
            .sorted { $0.words.count > $1.words.count }
        }
    }

    private struct Match {
        let pattern: Int
        let start: Int
        let end: Int
    }

    /// Matches the whole word list as a sequence of terms, or nil when any other word is present.
    private static func match(_ words: [Word], _ patterns: [Pattern]) -> [Match]? {
        var result: [Match] = []
        var position = 0
        while position < words.count {
            guard let found = term(at: position, in: words, patterns) else { return nil }
            result.append(found)
            position = found.end
        }
        return result
    }

    private static func term(at position: Int, in words: [Word], _ patterns: [Pattern]) -> Match? {
        for pattern in patterns where position + pattern.words.count <= words.count {
            let slice = words[position..<(position + pattern.words.count)].map(\.key)
            if slice == pattern.words {
                return Match(pattern: pattern.index, start: position, end: position + pattern.words.count)
            }
        }
        return nil
    }

    /// Cuts a leading or trailing run of terms that follows the saved order, such as "Inworld, Sage, Ryder".
    private static func trimmingOrderedRuns(_ segment: String, words: [Word], patterns: [Pattern]) -> String {
        var lower = 0
        var upper = words.count

        let leading = orderedRun(in: words, from: 0, patterns: patterns)
        if leading.count >= minimumOrderedRun {
            lower = leading.last!.end
        }
        let trailing = orderedRunEnding(in: words, before: words.count, after: lower, patterns: patterns)
        if trailing.count >= minimumOrderedRun {
            upper = trailing.first!.start
        }
        guard lower > 0 || upper < words.count else { return segment }
        guard lower < upper else { return "" }

        let start = words[lower].range.lowerBound
        let end = words[upper - 1].range.upperBound
        var kept = String(segment[start..<end])
        // Keep the sentence's own ending punctuation when the run came after it.
        let tail = segment[end...].prefix { !$0.isLetter && !$0.isNumber }
        if let mark = tail.first(where: { ".?!".contains($0) }) {
            kept.append(mark)
        }
        return kept
    }

    private static func orderedRun(in words: [Word], from start: Int, patterns: [Pattern]) -> [Match] {
        var run: [Match] = []
        var position = start
        while position < words.count, let found = term(at: position, in: words, patterns) {
            if let last = run.last, found.pattern <= last.pattern { break }
            run.append(found)
            position = found.end
        }
        return run
    }

    /// The longest ordered run that ends exactly at `end`, scanning back no further than `after`.
    private static func orderedRunEnding(in words: [Word], before end: Int, after floor: Int, patterns: [Pattern]) -> [Match] {
        var best: [Match] = []
        for start in floor..<end {
            let run = orderedRun(in: words, from: start, patterns: patterns)
            if let last = run.last, last.end == end, run.count > best.count {
                best = run
            }
        }
        return best
    }
}

/// A word in a transcript, compared without case or surrounding punctuation.
private struct Word {
    let key: String
    let range: Range<String.Index>

    static func split(_ text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWordCharacter = character.isLetter || character.isNumber || character == "'" || character == "’"
            if isWordCharacter, start == nil {
                start = index
            } else if !isWordCharacter, let begin = start {
                words.append(Word(text: text, range: begin..<index))
                start = nil
            }
            index = text.index(after: index)
        }
        if let begin = start {
            words.append(Word(text: text, range: begin..<text.endIndex))
        }
        return words
    }

    private init(text: String, range: Range<String.Index>) {
        self.range = range
        self.key = text[range].lowercased()
    }
}
