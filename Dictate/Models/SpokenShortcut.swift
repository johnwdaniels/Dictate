import Foundation
import SwiftData

/// A spoken phrase replaced with longer text after transcription. Not sent to Inworld.
@Model
final class SpokenShortcut {
    @Attribute(.unique) var id: UUID
    var phrase: String
    var expansion: String
    var createdAt: Date

    init(id: UUID = UUID(), phrase: String, expansion: String, createdAt: Date = .now) {
        self.id = id
        self.phrase = phrase
        self.expansion = expansion
        self.createdAt = createdAt
    }
}
