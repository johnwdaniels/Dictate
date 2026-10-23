import Foundation
import SwiftData

@MainActor
final class DictationHistoryStore: DictationHistorySaving {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func saveToHistory(
        _ text: String,
        durationSeconds: Double,
        appName: String,
        bundleID: String
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = DictationEntry(
            text: trimmed,
            durationSeconds: max(0, durationSeconds),
            wordCount: DictationEntry.wordCount(in: trimmed),
            destinationAppName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationBundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let context = container.mainContext
        context.insert(entry)
        try context.save()
    }
}

extension ModelContext {
    /// Deletes every entry in small batches so a large history is not loaded at once.
    func deleteAllDictationEntries() throws {
        while true {
            var descriptor = FetchDescriptor<DictationEntry>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 200
            let batch = try fetch(descriptor)
            if batch.isEmpty { return }
            for entry in batch {
                delete(entry)
            }
            try save()
        }
    }
}
