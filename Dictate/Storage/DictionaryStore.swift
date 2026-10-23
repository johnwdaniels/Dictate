import Foundation
import SwiftData

/// Reads the dictionary for a dictation session.
@MainActor
protocol DictationDictionary: AnyObject {
    func promptTerms() -> [String]
    func applyReplacements(to text: String) -> String
}

@MainActor
final class DictionaryStore: DictationDictionary {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func promptTerms() -> [String] {
        var descriptor = FetchDescriptor<DictionaryTerm>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = DictionaryTermRules.maximum
        let terms = (try? container.mainContext.fetch(descriptor)) ?? []
        return terms
            .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func applyReplacements(to text: String) -> String {
        let descriptor = FetchDescriptor<DictionaryReplacement>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let rules = (try? container.mainContext.fetch(descriptor)) ?? []
        let shortcutDescriptor = FetchDescriptor<SpokenShortcut>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let shortcuts = (try? container.mainContext.fetch(shortcutDescriptor)) ?? []
        let pairs = rules.map { (find: $0.find, replacement: $0.replacement) }
            + shortcuts.map { (find: $0.phrase, replacement: $0.expansion) }
        return DictionaryReplacements.apply(pairs, to: text)
    }
}
