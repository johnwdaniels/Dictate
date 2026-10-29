import Foundation

/// The text the pill shows while someone dictates: every finished phrase so far, then the phrase still being heard.
///
/// Inworld sends the current phrase again as it grows, then a final copy when a pause ends it. Showing only the current
/// phrase made the pill empty out at every pause, so it looked like it was waiting for sentences to finish.
struct LiveTranscript {
    private(set) var finished = ""

    /// The phrase still being heard replaces the previous partial and follows the finished text.
    func showing(partial: String) -> String {
        InworldSTTMessages.appending(finished, partial.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A finished phrase is kept, and the pill shows everything finished so far.
    mutating func finish(_ phrase: String) -> String {
        finished = InworldSTTMessages.appending(finished, phrase.trimmingCharacters(in: .whitespacesAndNewlines))
        return finished
    }
}
