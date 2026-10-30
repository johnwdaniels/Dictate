import AppKit
import ApplicationServices

/// Names and unusual spellings on screen, read through Accessibility, so Inworld spells them the way the screen does.
/// The app being dictated into comes first, then every other app with a window showing on any display, front to back.
/// Only the picked words leave the Mac, never the windows' text.
enum ScreenContext {
    static let enabledKey = "context.useScreenNames"
    static let maximumTerms = 60
    /// How long a dictation waits for the windows to be read. It overlaps the connection's handshake.
    static let wait: Duration = .milliseconds(120)

    private static let readBudget: CFAbsoluteTime = 0.4
    private static let otherAppBudget: CFAbsoluteTime = 0.25
    private static let maximumOtherApps = 8
    private static let maximumNodes = 2_500
    private static let maximumCharacters = 60_000
    private static let maximumCandidates = 250
    private static let cache = LastRead()
    /// Months, weekdays, languages and countries. They are always written with a capital, so the spell checker only
    /// knows them that way, and speech-to-text spells them right without help.
    private static let calendarWords: Set<String> = {
        let english = Locale(identifier: "en_US")
        let languages = Locale.LanguageCode.isoLanguageCodes.compactMap { english.localizedString(forLanguageCode: $0.identifier) }
        let regions = Locale.Region.isoRegions.compactMap { english.localizedString(forRegionCode: $0.identifier) }
        let nationalities = ["American", "British", "Canadian", "Australian", "Mexican", "Brazilian", "Indian", "European"]
        return Set(DateFormatter().monthSymbols + DateFormatter().weekdaySymbols + languages + regions + nationalities)
    }()

    /// Missing key means on, matching the Settings toggle's default.
    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// A read in progress for one dictation.
    struct ScreenRead: Sendable {
        let target: pid_t?
        fileprivate let order: AppOrder
        let task: Task<Void, Never>
    }

    /// Starts reading `target`, the app being dictated into, and every other app showing a window, all at once. It
    /// returns at once: even listing the windows happens in the background, so the key press never waits on it.
    static func readScreen(target: pid_t?) -> ScreenRead {
        let order = AppOrder()
        let task = Task.detached(priority: .userInitiated) {
            var pids = target.map { [$0] } ?? []
            pids += visibleProcessIDs().filter { $0 != target }.prefix(maximumOtherApps)
            order.set(pids)
            await withTaskGroup(of: Void.self) { group in
                for pid in pids {
                    group.addTask { read(pid: pid, wholeApp: pid != target) }
                }
            }
        }
        return ScreenRead(target: target, order: order, task: task)
    }

    /// Starts reading the focused window of `pid`, or with `wholeApp` all of its open windows, in the background.
    @discardableResult
    static func read(pid: pid_t, wholeApp: Bool = false) -> [String] {
        let strings = readStrings(pid: pid, wholeApp: wholeApp)
        cache.store(strings, for: pid)
        return strings
    }

    /// The text of every app in `read`, from this read where it finished within `wait`, or else from its last one.
    static func strings(from read: ScreenRead) async -> [String] {
        await withCheckedContinuation { continuation in
            let once = Once()
            Task {
                await read.task.value
                if once.claim() { continuation.resume() }
            }
            Task {
                try? await Task.sleep(for: wait)
                if once.claim() { continuation.resume() }
            }
        }
        let pids = read.order.pids ?? read.target.map { [$0] } ?? []
        return pids.flatMap { cache.strings(for: $0) }
    }

    /// Apps with a normal window showing on any display, front to back. Window titles would need Screen Recording;
    /// the owner of each window does not.
    private static func visibleProcessIDs() -> [pid_t] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        var result: [pid_t] = []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid != own, seen.insert(pid).inserted else { continue }
            result.append(pid)
        }
        return result
    }

    /// Words worth spelling the screen's way, in the order they were read, so the text around the cursor comes first:
    /// capitalized words and acronyms the spell checker doesn't know ("Kylan", "ZDR"), words with a capital inside
    /// ("iPhone", "ElevenLabs"), and names mixing letters and digits ("GPT-4o", "B2B").
    static func terms(in strings: [String], isKnownWord: (String) -> Bool) -> [String] {
        terms(from: candidates(in: strings, wordList: []), isKnownWord: isKnownWord)
    }

    /// Words found on screen, with whether the spell checker still has to rule each one out. Safe off the main thread:
    /// the macOS word list already rules out most ordinary words, so the spell checker, which needs the main thread,
    /// only sees what is left.
    static func candidates(in strings: [String], wordList: Set<String> = WordList.words) -> [Candidate] {
        var seen = Set<String>()
        var candidates: [Candidate] = []
        scan: for string in strings {
            for piece in string.split(whereSeparator: { $0.isWhitespace || $0 == "/" }) {
                guard let word = cleaned(piece), seen.insert(word).inserted,
                      !calendarWords.contains(word), let needsCheck = kind(of: word) else { continue }
                if needsCheck, isListed(word.lowercased(), in: wordList) { continue }
                candidates.append(Candidate(word: word, needsCheck: needsCheck))
                if candidates.count >= maximumCandidates { break scan }
            }
        }
        return candidates
    }

    /// The word list has base forms only, so "settings" and "messages" are checked as "setting" and "message" too.
    private static func isListed(_ word: String, in wordList: Set<String>) -> Bool {
        if wordList.contains(word) { return true }
        for suffix in ["s", "es", "ed", "ing", "er", "ly"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            if wordList.contains(String(word.dropLast(suffix.count))) { return true }
        }
        return false
    }

    struct Candidate: Sendable {
        let word: String
        let needsCheck: Bool
    }

    static func terms(from candidates: [Candidate], isKnownWord: (String) -> Bool) -> [String] {
        var terms: [String] = []
        for candidate in candidates {
            if candidate.needsCheck, isKnownWord(candidate.word.lowercased()) { continue }
            terms.append(candidate.word)
            if terms.count >= maximumTerms { break }
        }
        return terms
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?()[]{}<>\"'“”‘’*…")

    /// The word without surrounding punctuation or a possessive "'s". A curly apostrophe becomes a straight one,
    /// because Inworld rejects curly quotes and the word list spells contractions with "'".
    private static func cleaned(_ piece: Substring) -> String? {
        var word = piece.trimmingCharacters(in: edgePunctuation)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        if word.hasSuffix("'s") {
            word.removeLast(2)
        }
        guard (2...30).contains(word.count),
              word.allSatisfy({ $0.isLetter || $0.isNumber || "-.'".contains($0) }) else { return nil }
        return word
    }

    /// nil when the word isn't worth sending. Otherwise whether the spell checker still has to rule it out.
    private static func kind(of word: String) -> Bool? {
        let letters = word.filter(\.isLetter)
        let digits = word.filter(\.isNumber).count
        guard let first = letters.first else { return nil }
        let uppercase = letters.filter(\.isUppercase).count
        // File names such as "Dictate-v1.4.2.zip".
        if let dot = word.lastIndex(of: "."), word[word.index(after: dot)...].allSatisfy(\.isLowercase) { return nil }
        // IDs such as "C0C7P92UYGM": long, digits, no lowercase.
        if digits > 0, word.count >= 8, !letters.contains(where: \.isLowercase) { return nil }
        if digits > 0 {
            // "GPT-4o" and "B2B", but not "v1.4.2" or "10am".
            return letters.count >= 2 && uppercase > 0 ? false : nil
        }
        if first.isLowercase {
            // "iPhone", "eBay", "macOS", but not code such as "querySelectorAll", whose lowercase start runs longer.
            let start = letters.prefix { $0.isLowercase }.count
            return uppercase > 0 && letters.count >= 3 && start <= 3 ? false : nil
        }
        if uppercase == letters.count {
            // Acronyms such as "ZDR". Labels such as "SEND" are real words, so the spell checker drops them.
            return (2...6).contains(letters.count) ? true : nil
        }
        if uppercase > 1, word.dropFirst().contains(where: \.isUppercase) {
            // "ElevenLabs", "LinkedIn", "McKinsey".
            return false
        }
        return letters.count >= 3 ? true : nil
    }

    @MainActor
    static func terms(from candidates: [Candidate]) -> [String] {
        terms(from: candidates, isKnownWord: isEnglishWord)
    }

    /// Swaps a transcribed name for the screen's spelling when it is a near miss, such as "Kylen" for "Kylan".
    static func correctingNames(_ text: String, using terms: [String], isKnownWord: (String) -> Bool) -> String {
        guard !terms.isEmpty else { return text }
        var words: [(Range<String.Index>, String)] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
            guard let word, word.count >= 3, word.first?.isUppercase == true, !terms.contains(word) else { return }
            words.append((range, word))
        }
        var replacements: [(Range<String.Index>, String)] = []
        for (range, word) in words where !isKnownWord(word.lowercased()) {
            if let match = closestTerm(to: word, in: terms) {
                replacements.append((range, match))
            }
        }
        var result = text
        for (range, match) in replacements.reversed() {
            result.replaceSubrange(range, with: match)
        }
        return result
    }

    @MainActor
    static func correctingNames(_ text: String, using terms: [String]) -> String {
        correctingNames(text, using: terms, isKnownWord: isEnglishWord)
    }

    /// The one term within a small edit distance that starts with the same letter. A tie means no swap.
    private static func closestTerm(to word: String, in terms: [String]) -> String? {
        let allowed = word.count <= 4 ? 1 : 2
        let lowered = word.lowercased()
        var best: (term: String, distance: Int)?
        var tied = false
        for term in terms where term.first?.lowercased() == word.first?.lowercased() {
            guard abs(term.count - word.count) <= allowed else { continue }
            let distance = editDistance(lowered, term.lowercased())
            guard distance <= allowed else { continue }
            if let current = best, distance >= current.distance {
                if distance == current.distance, term != current.term { tied = true }
                continue
            }
            best = (term, distance)
            tied = false
        }
        return tied ? nil : best?.term
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// The spell checker takes a tenth of a millisecond per word, two when it also has to list completions, and a
    /// window repeats most of its words.
    @MainActor private static var knownWords: [String: Bool] = [:]

    /// Whether `word`, lowercased, is an ordinary English word. The spell checker also accepts first names such as
    /// "nikki", so a word it knows only counts when it also offers it as a completion, which it never does for names.
    /// Names that are ordinary words too, such as "Mark" or "Grace", count as words: they are spelled the same.
    @MainActor
    static func isEnglishWord(_ word: String) -> Bool {
        if let known = knownWords[word] { return known }
        let checker = NSSpellChecker.shared
        var known = checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
        if known {
            let range = NSRange(location: 0, length: (word as NSString).length)
            let completions = checker.completions(
                forPartialWordRange: range, in: word, language: "en", inSpellDocumentWithTag: 0
            ) ?? []
            known = completions.contains(word)
        }
        if knownWords.count > 20_000 { knownWords.removeAll() }
        knownWords[word] = known
        return known
    }

    /// Runs the screen's words past the spell checker while nobody is dictating, so a dictation finds them answered.
    private static func warmSpelling(_ strings: [String]) async {
        let found = candidates(in: strings)
        await MainActor.run { _ = terms(from: found) }
    }

    /// Reads the whole screen once at launch, then each app's window when it comes to the front, so the first dictation
    /// there already has its names.
    @MainActor
    static func startWarming() {
        if isEnabled {
            let screen = readScreen(target: nil)
            Task.detached(priority: .utility) {
                _ = WordList.words.count
                await screen.task.value
                await warmSpelling((screen.order.pids ?? []).flatMap { cache.strings(for: $0) })
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard isEnabled,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            let pid = app.processIdentifier
            Task.detached(priority: .utility) { await warmSpelling(read(pid: pid)) }
        }
    }

    // MARK: - Reading the window

    private static func readStrings(pid: pid_t, wholeApp: Bool) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        // Chrome and Electron apps only expose web content once an assistive app asks for it.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let deadline = CFAbsoluteTimeGetCurrent() + (wholeApp ? otherAppBudget : readBudget)
        var roots: [AXUIElement] = []
        if wholeApp {
            // Another app: every window that isn't minimized, since any of them may be on another display.
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                roots = windows.filter { !isMinimized($0) }
            }
        } else if var node = element(app, kAXFocusedUIElementAttribute) {
            // The app being dictated into: start a few levels above the field being typed in, where the conversation
            // is, then the rest of the window.
            for _ in 0..<6 where CFAbsoluteTimeGetCurrent() < deadline {
                guard let parent = element(node, kAXParentAttribute), role(of: parent) != kAXWindowRole else { break }
                node = parent
            }
            roots.append(node)
        }
        if !wholeApp, let window = element(app, kAXFocusedWindowAttribute) {
            roots.append(window)
        }

        let attributes = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXChildrenAttribute] as CFArray
        var queue = roots
        var index = 0
        var visited = Set<AXUIElement>()
        var strings: [String] = []
        var characters = 0
        while index < queue.count, visited.count < maximumNodes, characters < maximumCharacters,
              CFAbsoluteTimeGetCurrent() < deadline {
            let node = queue[index]
            index += 1
            guard visited.insert(node).inserted else { continue }
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(node, attributes, [], &values) == .success,
                  let values = values as? [AnyObject] else { continue }
            for value in values {
                if let string = value as? String, !string.isEmpty {
                    let piece = String(string.prefix(2_000))
                    strings.append(piece)
                    characters += piece.count
                } else if let children = value as? [AXUIElement] {
                    queue.append(contentsOf: children)
                }
            }
        }
        return strings
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// The macOS word list, lowercased, loaded once in the background. Empty if the file is missing.
enum WordList {
    static let words: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()
}

/// The apps one read covers, known once the window list comes back.
final class AppOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [pid_t]?

    var pids: [pid_t]? {
        lock.withLock { stored }
    }

    func set(_ pids: [pid_t]) {
        lock.withLock { stored = pids }
    }
}

/// The last read of each app, used when this read is still going.
private final class LastRead: @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [pid_t: [String]] = [:]

    func store(_ strings: [String], for pid: pid_t) {
        lock.withLock { reads[pid] = strings }
    }

    func strings(for pid: pid_t) -> [String] {
        lock.withLock { reads[pid] ?? [] }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
