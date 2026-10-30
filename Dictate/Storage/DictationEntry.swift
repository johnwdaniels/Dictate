import Foundation
import SwiftData

@Model
final class DictationEntry {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var durationSeconds: Double
    var wordCount: Int
    var destinationAppName: String = ""
    var destinationBundleID: String = ""
    /// The screen's names sent to Inworld as hints for this dictation, joined by ", ".
    var screenHints: String = ""

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        durationSeconds: Double,
        wordCount: Int,
        destinationAppName: String = "",
        destinationBundleID: String = "",
        screenHints: [String] = []
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.destinationAppName = destinationAppName
        self.destinationBundleID = destinationBundleID
        self.screenHints = screenHints.joined(separator: ", ")
    }

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }
}
