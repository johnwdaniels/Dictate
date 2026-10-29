import AppKit
import ApplicationServices

/// Fits a dictation onto the text already before the cursor. It adds a space when it would run into the end of the last
/// one ("today?To maximize"), and lowercases the first word when the sentence is still going ("duo With the").
enum SmartSpacing {
    /// How long the previous dictation still counts as what is before the cursor, when the app can't be asked.
    static let rememberFor: TimeInterval = 120
    /// Enough to see past a trailing space and closing quotes to the last real character.
    private static let lookBack = 4

    private static let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "/", "-", "@", "#"]
    private static let noSpaceBefore: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "'", "’", "”", "%", "…"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
    private static let closingMarks: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]

    private static var lastPaste: (bundleID: String, time: Date, tail: String)?

    /// `previous` is the character just before the cursor, or nil at the start of the field or when it is unknown.
    static func spaced(_ text: String, after previous: Character?) -> String {
        guard let previous, let first = text.first,
              !previous.isWhitespace, !noSpaceAfter.contains(previous),
              !first.isWhitespace, !noSpaceBefore.contains(first) else { return text }
        return " " + text
    }

    /// True when `before`, the text just before the cursor, stops partway through a sentence.
    static func continuesSentence(_ before: String) -> Bool {
        for character in before.reversed() {
            if character.isNewline { return false }
            if character.isWhitespace || closingMarks.contains(character) { continue }
            return !sentenceEnds.contains(character)
        }
        return false
    }

    /// Lowercases the first word when its capital only came from starting a new dictation. "I", acronyms, `names`, and
    /// words the spell checker doesn't know, which are usually names, keep theirs.
    static func lowercasingFirstWord(
        _ text: String,
        keeping names: Set<String>,
        isKnownWord: (String) -> Bool
    ) -> String {
        guard let start = text.firstIndex(where: \.isLetter), text[start].isUppercase else { return text }
        let end = text[start...].firstIndex { !($0.isLetter || $0 == "'" || $0 == "’") } ?? text.endIndex
        let word = String(text[start..<end])
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return text }
        if word.dropFirst().contains(where: \.isUppercase) { return text }
        if names.contains(word) || !isKnownWord(word.lowercased()) { return text }
        return text.replacingCharacters(in: start...start, with: text[start].lowercased())
    }

    /// The text to paste into the focused field of `bundleID`. `names` keep their capital mid-sentence.
    @MainActor
    static func prepare(_ text: String, bundleID: String, names: Set<String> = [], now: Date = Date()) -> String {
        let before: String?
        switch textBeforeCursor() {
        case .known(let text):
            before = text
        case .unknown:
            // Some apps don't share their text. Fall back to how this app's last dictation ended.
            if let lastPaste, lastPaste.bundleID == bundleID, now.timeIntervalSince(lastPaste.time) < rememberFor {
                before = lastPaste.tail
            } else {
                before = nil
            }
        }
        var result = text
        if let before, continuesSentence(before) {
            result = lowercasingFirstWord(result, keeping: names, isKnownWord: isEnglishWord)
        }
        result = spaced(result, after: before?.last)
        if !result.isEmpty {
            lastPaste = (bundleID, now, String(result.suffix(lookBack)))
        }
        return result
    }

    @MainActor
    private static func isEnglishWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    private enum Before {
        /// An empty string means the cursor is at the start of the field.
        case known(String)
        case unknown
    }

    @MainActor
    private static func textBeforeCursor() -> Before {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = focused as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return .unknown }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return .unknown }
        guard selection.location > 0 else { return .known("") }

        let length = min(selection.location, lookBack)
        var previousRange = CFRange(location: selection.location - length, length: length)
        if let rangeArgument = AXValueCreate(.cfRange, &previousRange) {
            var piece: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeArgument,
                &piece
            ) == .success, let string = piece as? String, !string.isEmpty {
                return .known(string)
            }
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let string = value as? String else { return .unknown }
        let utf16 = string.utf16
        guard let end = utf16.index(utf16.startIndex, offsetBy: selection.location, limitedBy: utf16.endIndex),
              let start = utf16.index(end, offsetBy: -length, limitedBy: utf16.startIndex),
              let from = start.samePosition(in: string), let to = end.samePosition(in: string) else { return .unknown }
        return .known(String(string[from..<to]))
    }
}
