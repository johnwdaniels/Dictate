import AppKit
import ApplicationServices

/// Adds a space before a dictation that lands right after other text, so a second dictation doesn't run into the end of
/// the first ("today?To maximize").
enum SmartSpacing {
    /// How long the previous dictation still counts as what is before the cursor, when the app can't be asked.
    static let rememberFor: TimeInterval = 120

    private static let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "/", "-", "@", "#"]
    private static let noSpaceBefore: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "'", "’", "”", "%", "…"]

    private static var lastPaste: (bundleID: String, time: Date, last: Character)?

    /// `previous` is the character just before the cursor, or nil at the start of the field or when it is unknown.
    static func spaced(_ text: String, after previous: Character?) -> String {
        guard let previous, let first = text.first,
              !previous.isWhitespace, !noSpaceAfter.contains(previous),
              !first.isWhitespace, !noSpaceBefore.contains(first) else { return text }
        return " " + text
    }

    /// The text to paste into the focused field of `bundleID`.
    @MainActor
    static func prepare(_ text: String, bundleID: String, now: Date = Date()) -> String {
        let previous: Character?
        switch characterBeforeCursor() {
        case .known(let character):
            previous = character
        case .unknown:
            // Some apps don't share their text. Fall back to how this app's last dictation ended.
            if let lastPaste, lastPaste.bundleID == bundleID, now.timeIntervalSince(lastPaste.time) < rememberFor {
                previous = lastPaste.last
            } else {
                previous = nil
            }
        }
        let result = spaced(text, after: previous)
        if let last = result.last {
            lastPaste = (bundleID, now, last)
        }
        return result
    }

    private enum Before {
        /// nil means the cursor is at the start of the field, or text is selected and will be replaced.
        case known(Character?)
        case unknown
    }

    @MainActor
    private static func characterBeforeCursor() -> Before {
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
        guard selection.location > 0 else { return .known(nil) }

        var previousRange = CFRange(location: selection.location - 1, length: 1)
        if let rangeArgument = AXValueCreate(.cfRange, &previousRange) {
            var piece: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeArgument,
                &piece
            ) == .success, let string = piece as? String, let character = string.last {
                return .known(character)
            }
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let string = value as? String else { return .unknown }
        let utf16 = string.utf16
        guard selection.location <= utf16.count,
              let end = utf16.index(utf16.startIndex, offsetBy: selection.location, limitedBy: utf16.endIndex),
              let endIndex = end.samePosition(in: string), endIndex > string.startIndex else { return .unknown }
        return .known(string[string.index(before: endIndex)])
    }
}
