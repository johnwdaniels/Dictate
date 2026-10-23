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

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        durationSeconds: Double,
        wordCount: Int,
        destinationAppName: String = "",
        destinationBundleID: String = ""
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.destinationAppName = destinationAppName
        self.destinationBundleID = destinationBundleID
    }

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }
}
