import Foundation
import SwiftData

/// A local find-and-replace applied after transcription. These are not sent to Inworld.
@Model
final class DictionaryReplacement {
    @Attribute(.unique) var id: UUID
    var find: String
    var replacement: String
    var createdAt: Date

    init(id: UUID = UUID(), find: String, replacement: String, createdAt: Date = .now) {
        self.id = id
        self.find = find
        self.replacement = replacement
        self.createdAt = createdAt
    }
}
