import Foundation
import SwiftData

@Model
final class DictionaryTerm {
    @Attribute(.unique) var id: UUID
    var term: String
    var createdAt: Date

    init(id: UUID = UUID(), term: String, createdAt: Date = .now) {
        self.id = id
        self.term = term
        self.createdAt = createdAt
    }
}
