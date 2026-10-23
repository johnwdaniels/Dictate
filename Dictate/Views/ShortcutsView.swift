import SwiftData
import SwiftUI

struct ShortcutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpokenShortcut.createdAt, order: .forward) private var shortcuts: [SpokenShortcut]

    @State private var phrase = ""
    @State private var expansion = ""
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editor
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say a short phrase while dictating, and Dictate replaces it with the longer text.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Example")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("You say")
                        .foregroundStyle(.secondary)
                    Text("“my email”")
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text("you@example.com")
                        .foregroundStyle(.tint)
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                ForEach(SpokenShortcutRules.ideas) { idea in
                    Button(idea.title) {
                        phrase = idea.phrase
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("Phrase you say", text: $phrase)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Text("→")
                    .foregroundStyle(.secondary)
                TextField("Text to insert", text: $expansion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(!canAdd)
            }

            if let issue {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if shortcuts.isEmpty {
            Text("No shortcuts yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(shortcuts) { shortcut in
                    Text("\(shortcut.phrase) → \(shortcut.expansion)")
                        .lineLimit(2)
                        .tag(shortcut.id)
                        .contextMenu {
                            Button("Delete") { delete(shortcut) }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { delete(shortcut) }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .onDeleteCommand(perform: deleteSelected)
        }
    }

    private var existingPhrases: [String] {
        shortcuts.map(\.phrase)
    }

    private var issue: String? {
        SpokenShortcutRules.issue(for: phrase, expansion: expansion, existing: existingPhrases)
    }

    private var canAdd: Bool {
        SpokenShortcutRules.canAdd(phrase: phrase, expansion: expansion, existing: existingPhrases)
    }

    private func add() {
        let spoken = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let inserted = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpokenShortcutRules.canAdd(phrase: spoken, expansion: inserted, existing: existingPhrases) else { return }
        modelContext.insert(SpokenShortcut(phrase: spoken, expansion: inserted))
        try? modelContext.save()
        phrase = ""
        expansion = ""
    }

    private func delete(_ shortcut: SpokenShortcut) {
        if selection == shortcut.id { selection = nil }
        modelContext.delete(shortcut)
        try? modelContext.save()
    }

    private func deleteSelected() {
        guard let selection, let shortcut = shortcuts.first(where: { $0.id == selection }) else { return }
        delete(shortcut)
    }
}
