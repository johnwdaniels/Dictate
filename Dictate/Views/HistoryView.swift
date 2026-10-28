import AppKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var limit = HistoryList.pageSize
    @State private var confirmClear = false

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HistoryList(search: trimmedSearch, limit: limit) {
            limit += HistoryList.pageSize
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear All", systemImage: "trash") {
                    confirmClear = true
                }
                .help("Clear all history")
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                try? modelContext.deleteAllDictationEntries()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved dictation.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryList: View {
    static let pageSize = 200

    @Query private var entries: [DictationEntry]
    @Environment(\.modelContext) private var modelContext

    private let searchText: String
    private let fetchLimit: Int
    let onLoadMore: () -> Void

    @State private var selection: UUID?
    @State private var expandedID: UUID?
    @State private var copiedID: UUID?
    @State private var copyReset: Task<Void, Never>?
    @State private var copyMonitor: HistoryCopyMonitor?

    init(search: String, limit: Int, onLoadMore: @escaping () -> Void) {
        self.searchText = search
        self.fetchLimit = limit
        self.onLoadMore = onLoadMore
        var descriptor = FetchDescriptor<DictationEntry>(
            predicate: Self.predicate(matching: search),
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        _entries = Query(descriptor)
    }

    var body: some View {
        let _ = copyMonitor?.copy = { copySelection() }
        return VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView(
                    searchIsIdle ? "No Dictations Yet" : "No Matches",
                    systemImage: "clock",
                    description: Text(searchIsIdle ? "Transcripts will show up here." : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(dayGroups) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                row(entry)
                                    .tag(entry.id)
                                    .contextMenu {
                                        Button("Copy") { copy(entry) }
                                        Button("Delete", role: .destructive) { delete(entry) }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("Delete", role: .destructive) { delete(entry) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onDeleteCommand {
                    deleteSelection()
                }

                if entries.count >= fetchLimit {
                    Button("Show More") {
                        onLoadMore()
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: startCopyMonitor)
        .onDisappear(perform: stopCopyMonitor)
    }

    private var searchIsIdle: Bool {
        searchText.isEmpty
    }

    private var dayGroups: [HistoryDayGroup] {
        HistoryDayGroup.make(from: entries)
    }

    @ViewBuilder
    private func row(_ entry: DictationEntry) -> some View {
        let expanded = expandedID == entry.id
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .lineLimit(expanded ? nil : 2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                Text(wordLabel(entry.wordCount))
                Spacer(minLength: 8)
                Button(copiedID == entry.id ? "Copied" : "Copy") {
                    selection = entry.id
                    copy(entry)
                }
                .buttonStyle(.borderless)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = entry.id
            expandedID = expanded ? nil : entry.id
        }
    }

    private func wordLabel(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    private func copy(_ entry: DictationEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(entry.text, forType: .string) else { return }
        copiedID = entry.id
        copyReset?.cancel()
        let copied = entry.id
        copyReset = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, copiedID == copied else { return }
            copiedID = nil
        }
    }

    private func delete(_ entry: DictationEntry) {
        if selection == entry.id { selection = nil }
        if expandedID == entry.id { expandedID = nil }
        if copiedID == entry.id { copiedID = nil }
        modelContext.delete(entry)
        try? modelContext.save()
    }

    private func deleteSelection() {
        guard let selection, let entry = entries.first(where: { $0.id == selection }) else { return }
        delete(entry)
    }

    private func copySelection() -> Bool {
        guard let selection, let entry = entries.first(where: { $0.id == selection }) else { return false }
        copy(entry)
        return true
    }

    private func startCopyMonitor() {
        let monitor = HistoryCopyMonitor()
        monitor.start()
        copyMonitor = monitor
    }

    private func stopCopyMonitor() {
        copyMonitor?.stop()
        copyMonitor = nil
    }

    private static func predicate(matching search: String) -> Predicate<DictationEntry>? {
        guard !search.isEmpty else { return nil }
        return #Predicate<DictationEntry> { entry in
            entry.text.localizedStandardContains(search)
        }
    }
}

private struct HistoryDayGroup: Identifiable {
    let day: Date
    let title: String
    var entries: [DictationEntry]

    var id: Date { day }

    static func make(from entries: [DictationEntry], calendar: Calendar = .current) -> [HistoryDayGroup] {
        var groups: [HistoryDayGroup] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if let index = groups.indices.last, groups[index].day == day {
                groups[index].entries.append(entry)
            } else {
                groups.append(HistoryDayGroup(day: day, title: title(for: entry.createdAt, calendar: calendar), entries: [entry]))
            }
        }
        return groups
    }

    private static func title(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .long, time: .omitted)
    }
}

private final class HistoryCopyMonitor {
    var copy: (() -> Bool)?
    private var monitor: Any?

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "c",
                  !event.isARepeat
            else {
                return event
            }
            if Self.isEditingText(NSApp.keyWindow?.firstResponder) {
                return event
            }
            return self.copy?() == true ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func isEditingText(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField
    }
}
