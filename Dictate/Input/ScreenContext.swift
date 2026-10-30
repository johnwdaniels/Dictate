import AppKit
import ApplicationServices

/// Names and unusual spellings on screen, read through Accessibility, so Inworld spells them the way the screen does.
/// The app being dictated into comes first, then every other app with a window showing on any display, front to back.
/// Only the picked words leave the Mac, never the windows' text.
enum ScreenContext {
    static let enabledKey = "context.useScreenNames"
    /// Screen words kept for fixing the transcript afterwards. These never reach Inworld, so there can be many.
    static let maximumTerms = 300
    /// Screen words sent to Inworld as hints. Each one nudges what it hears, so only the window being typed in sends any.
    static let maximumHints = 20
    /// How long a dictation waits for the windows to be read. It overlaps the connection's handshake.
    static let wait: Duration = .milliseconds(120)

    private static let readBudget: CFAbsoluteTime = 0.4
    private static let otherAppBudget: CFAbsoluteTime = 0.25
    private static let maximumOtherApps = 8
    private static let maximumNodes = 2_500
    private static let maximumCharacters = 60_000
    private static let maximumCandidates = 600
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
        let text = readStrings(pid: pid, wholeApp: wholeApp)
        cache.store(text, for: pid)
        return text.strings
    }

    /// One app's text in reading order. The first `nearCount` strings come from around the field being typed in.
    struct WindowText: Sendable {
        var strings: [String] = []
        var nearCount = 0
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
        return pids.flatMap { cache.text(for: $0).strings }
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
                let listed = needsCheck && isListed(word.lowercased(), in: wordList)
                candidates.append(Candidate(word: word, needsCheck: needsCheck, listed: listed))
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
        /// In the macOS word list. That list is old and full of rare words such as "arx", so a listed word is only
        /// ordinary once the spell checker knows it too.
        var listed = false
    }

    /// `isSpelledWord` rules on words the word list already has; without it `isKnownWord` rules on every word.
    static func terms(
        from candidates: [Candidate],
        limit: Int = maximumTerms,
        isKnownWord: (String) -> Bool,
        isSpelledWord: ((String) -> Bool)? = nil
    ) -> [String] {
        var terms: [String] = []
        for candidate in candidates {
            if candidate.needsCheck {
                let word = candidate.word.lowercased()
                let isOrdinary = candidate.listed ? (isSpelledWord?(word) ?? isKnownWord(word)) : isKnownWord(word)
                if isOrdinary { continue }
            }
            terms.append(candidate.word)
            if terms.count >= limit { break }
        }
        return terms
    }

    /// Runs of two to four capitalized words around a term, such as "Arx Media" or "Pocket FM", so a company or full
    /// name can be sent whole and recognized whole.
    static func phrases(in strings: [String], containing terms: [String]) -> [String] {
        let termSet = Set(terms)
        var seen = Set<String>()
        var phrases: [String] = []
        for string in strings {
            var run: [String] = []
            func flush() {
                if (2...4).contains(run.count), run.contains(where: termSet.contains) {
                    let phrase = run.joined(separator: " ")
                    if seen.insert(phrase).inserted { phrases.append(phrase) }
                }
                run = []
            }
            for piece in string.split(whereSeparator: \.isWhitespace) {
                guard let word = cleaned(piece), let first = word.first, first.isUppercase || first.isNumber else {
                    flush()
                    continue
                }
                run.append(word)
                // A comma or full stop ends the name: "Arx Media, Pocket FM".
                if let last = piece.last, ",;:.!?)".contains(last) { flush() }
            }
            flush()
            if phrases.count >= maximumTerms { break }
        }
        return phrases
    }

    /// The hints for Inworld: terms from the window being typed in, each as its whole phrase where it has one.
    static func hints(from terms: [String], phrases: [String]) -> [String] {
        var seen = Set<String>()
        var hints: [String] = []
        for term in terms {
            let hint = phrases.first { $0.split(separator: " ").contains(Substring(term)) } ?? term
            if seen.insert(hint).inserted { hints.append(hint) }
            if hints.count >= maximumHints { break }
        }
        return hints
    }

    /// What one dictation takes from the screen.
    struct Words: Sendable {
        var hints: [String] = []
        var terms: [String] = []
        var phrases: [String] = []
    }

    /// Hints from the window being typed in, and terms and phrases from every window, for fixing the transcript.
    static func words(from read: ScreenRead) async -> Words {
        let strings = await strings(from: read)
        let target = read.target.map { cache.text(for: $0) } ?? WindowText()
        // Sorting the words happens here, off the main thread. Only words that might be names reach the spell checker
        // on the main thread, and the screen's words are usually already checked by the time a dictation starts.
        let found = candidates(in: strings)
        let terms = await MainActor.run { Self.terms(from: found) }
        let phrases = phrases(in: strings, containing: terms)
        let ranked = ranked(terms, phrases: phrases, in: strings, target: target, ownName: ownName)
        return Words(hints: hints(from: ranked, phrases: phrases), terms: terms, phrases: phrases)
    }

    /// The Mac user's own name. It's on screen everywhere and rarely said, so it never takes a hint.
    private static let ownName = Set(NSFullUserName().split(separator: " ").map(String.init))

    /// The terms of the window being typed in, most likely to be said first. Scored by, in order of weight:
    /// being near the field, and lower down there, where the newest messages are; showing up often; being a full or
    /// oddly spelled name, such as "Arx Media" or "PocketFM"; and showing in another app too. Without the window's
    /// text, every term is scored.
    static func ranked(
        _ terms: [String],
        phrases: [String],
        in strings: [String],
        target: WindowText,
        ownName: Set<String> = []
    ) -> [String] {
        let termSet = Set(terms)
        func occurrences(in strings: ArraySlice<String>, _ found: (String, Int) -> Void) {
            for (index, string) in zip(strings.indices, strings) {
                for piece in string.split(whereSeparator: { $0.isWhitespace || $0 == "/" }) {
                    if let word = cleaned(piece), termSet.contains(word) { found(word, index) }
                }
            }
        }
        var counts: [String: Int] = [:]
        occurrences(in: strings[...]) { word, _ in counts[word, default: 0] += 1 }
        var inWindow: [String: Int] = [:]
        occurrences(in: target.strings[...]) { word, _ in inWindow[word, default: 0] += 1 }
        var lastNear: [String: Int] = [:]
        occurrences(in: target.strings.prefix(target.nearCount)) { word, index in lastNear[word] = index }
        let phraseWords = Set(phrases.flatMap { $0.split(separator: " ").map(String.init) })

        func score(_ term: String) -> Double {
            var score = min(Double(counts[term] ?? 0), 6) * 0.5
            if let index = lastNear[term] {
                score += 2 + 3 * Double(index + 1) / Double(max(target.nearCount, 1))
            }
            if phraseWords.contains(term) || term.dropFirst().contains(where: { $0.isUppercase || $0.isNumber }) {
                score += 1.5
            }
            if (counts[term] ?? 0) > (inWindow[term] ?? 0) { score += 1 }
            return score
        }
        let pool = target.strings.isEmpty ? terms : terms.filter { inWindow[$0] != nil }
        return pool.enumerated()
            .filter { !ownName.contains($0.element) }
            .map { (term: $0.element, order: $0.offset, score: score($0.element)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.term)
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
        terms(from: candidates, isKnownWord: isEnglishWord, isSpelledWord: isSpelled)
    }

    /// Puts the screen's spelling back into the transcript, in three passes:
    /// a term said in pieces is joined ("Pocket FM" to "PocketFM"), a word that sounds like one in a screen phrase is
    /// swapped when the rest of the phrase matches ("Arcs Media" to "Arx Media"), and a name that is a near miss is
    /// swapped ("Kylen" to "Kylan"). Nothing here reaches Inworld, so it adds no bias and no wait.
    static func correctingNames(
        _ text: String,
        using terms: [String],
        phrases: [String] = [],
        isKnownWord: (String) -> Bool
    ) -> String {
        guard !terms.isEmpty else { return text }
        var result = joiningSplitTerms(text, terms: terms)
        result = correctingPhrases(result, phrases: phrases, terms: Set(terms))
        var replacements: [(Range<String.Index>, String)] = []
        // The spell checker is the slow part, so it only rules on words that are near a term.
        for (range, word) in words(in: result)
        where word.count >= 3 && word.first?.isUppercase == true && !terms.contains(word) {
            if let match = closestTerm(to: word, in: terms), !isKnownWord(word.lowercased()) {
                replacements.append((range, match))
            }
        }
        return replacing(replacements, in: result)
    }

    @MainActor
    static func correctingNames(_ text: String, using terms: [String], phrases: [String]) -> String {
        correctingNames(text, using: terms, phrases: phrases, isKnownWord: isEnglishWord)
    }

    private static func words(in text: String) -> [(Range<String.Index>, String)] {
        var words: [(Range<String.Index>, String)] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
            if let word { words.append((range, word)) }
        }
        return words
    }

    private static func replacing(_ replacements: [(Range<String.Index>, String)], in text: String) -> String {
        var result = text
        for (range, replacement) in replacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func letters(_ word: some StringProtocol) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Two or three words in a row, with only spaces or hyphens between them, that spell a term once joined.
    private static func joiningSplitTerms(_ text: String, terms: [String]) -> String {
        var byLetters: [String: String] = [:]
        for term in terms where letters(term).count >= 4 && byLetters[letters(term)] == nil {
            byLetters[letters(term)] = term
        }
        let words = words(in: text)
        var replacements: [(Range<String.Index>, String)] = []
        var index = 0
        while index < words.count {
            var length = 1
            for count in [3, 2] where index + count <= words.count {
                let span = words[index..<index + count]
                let joinedBySpaces = zip(span, span.dropFirst()).allSatisfy { left, right in
                    text[left.0.upperBound..<right.0.lowerBound].allSatisfy { $0 == " " || $0 == "-" }
                }
                guard joinedBySpaces, let term = byLetters[span.map { letters($0.1) }.joined()] else { continue }
                replacements.append((span.first!.0.lowerBound..<span.last!.0.upperBound, term))
                length = count
                break
            }
            index += length
        }
        return replacing(replacements, in: text)
    }

    /// A phrase from the screen said with one word misheard, such as "Arcs Media" for "Arx Media". The other words
    /// must match, which is what makes it safe to swap even an ordinary word such as "arcs".
    private static func correctingPhrases(_ text: String, phrases: [String], terms: Set<String>) -> String {
        var result = text
        for phrase in phrases {
            let parts = phrase.split(separator: " ").map(String.init)
            let words = words(in: result)
            guard parts.count >= 2, words.count >= parts.count else { continue }
            var replacements: [(Range<String.Index>, String)] = []
            var index = 0
            while index + parts.count <= words.count {
                var misheard: Int?
                var matches = true
                for (offset, part) in parts.enumerated() {
                    let word = words[index + offset].1
                    if word.lowercased() == part.lowercased() { continue }
                    if misheard == nil, terms.contains(part), soundsAlike(word, part) {
                        misheard = offset
                    } else {
                        matches = false
                        break
                    }
                }
                if matches, let misheard {
                    replacements.append((words[index + misheard].0, parts[misheard]))
                    index += parts.count
                } else {
                    index += 1
                }
            }
            result = replacing(replacements, in: result)
        }
        return result
    }

    private static func soundsAlike(_ word: String, _ term: String) -> Bool {
        if soundKey(word) == soundKey(term) { return true }
        let allowed = term.count <= 4 ? 1 : 2
        return word.first?.lowercased() == term.first?.lowercased()
            && editDistance(word.lowercased(), term.lowercased()) <= allowed
    }

    /// A rough key for how an English word sounds: "arcs" and "arx" are both "arks", "Nicki" and "Nikki" both "nk".
    static func soundKey(_ word: String) -> String {
        var spelled = word.lowercased().filter(\.isLetter)
        for (from, to) in [("ph", "f"), ("ck", "k"), ("x", "ks"), ("q", "k"), ("z", "s")] {
            spelled = spelled.replacingOccurrences(of: from, with: to)
        }
        let letters = Array(spelled)
        var key: [Character] = []
        for (index, letter) in letters.enumerated() {
            var sound = letter
            if letter == "c" {
                let next = index + 1 < letters.count ? letters[index + 1] : " "
                sound = "eiy".contains(next) ? "s" : "k"
            }
            if index > 0, "aeiouyhw".contains(sound) { continue }
            if key.last == sound { continue }
            key.append(sound)
        }
        return String(key)
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
        var known = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
        if known, let language = completionLanguage {
            known = completions(of: word, language: language).contains(word)
        }
        if knownWords.count > 20_000 { knownWords.removeAll() }
        knownWords[word] = known
        return known
    }

    /// The language whose completions list ordinary words, or nil when none does on this Mac. Without it every word
    /// would look like a name, so the check falls back to the spell checker alone.
    @MainActor static let completionLanguage: String? = ["en", "en_US", "en_GB"].first {
        completions(of: "email", language: $0).contains("email")
    }

    @MainActor
    private static func completions(of word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return NSSpellChecker.shared.completions(
            forPartialWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0
        ) ?? []
    }

    @MainActor private static var spelledWords: [String: Bool] = [:]

    /// Whether the spell checker knows `word`, for words the word list has, where its completions aren't needed.
    @MainActor
    static func isSpelled(_ word: String) -> Bool {
        if let known = spelledWords[word] { return known }
        let known = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
        if spelledWords.count > 20_000 { spelledWords.removeAll() }
        spelledWords[word] = known
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
                await warmSpelling((screen.order.pids ?? []).flatMap { cache.text(for: $0).strings })
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

    private static func readStrings(pid: pid_t, wholeApp: Bool) -> WindowText {
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
        var visited = Set<AXUIElement>()
        var strings: [String] = []
        var characters = 0
        var nearCount = 0
        // One root at a time, so the area around the field is read in full before the rest of the window.
        for (rootIndex, root) in roots.enumerated() {
            var queue = [root]
            var index = 0
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
            if rootIndex == 0, !wholeApp { nearCount = strings.count }
        }
        return WindowText(strings: strings, nearCount: nearCount)
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

/// The ordinary words of the macOS word list, loaded once in the background. Capitalized entries are names, such as
/// "Marvin", so they're left out. Empty if the file is missing.
enum WordList {
    static let words: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").filter { $0.first?.isLowercase == true }.map(String.init))
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
    private var reads: [pid_t: ScreenContext.WindowText] = [:]

    func store(_ text: ScreenContext.WindowText, for pid: pid_t) {
        lock.withLock { reads[pid] = text }
    }

    func text(for pid: pid_t) -> ScreenContext.WindowText {
        lock.withLock { reads[pid] ?? ScreenContext.WindowText() }
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
