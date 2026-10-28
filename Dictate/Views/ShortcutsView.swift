import SwiftData
import SwiftUI

struct ShortcutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpokenShortcut.createdAt, order: .forward) private var shortcuts: [SpokenShortcut]

    @State private var phrase = ""
    @State private var expansion = ""

    var body: some View {
        Form {
            newShortcutSection
            shortcutsSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newShortcutSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Phrase you say", text: $phrase, prompt: Text("my email"))
                    .onSubmit(add)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Text to insert", text: $expansion, prompt: Text("Text to insert"))
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(!canAdd)
            }
            if let issue {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                ForEach(SpokenShortcutRules.ideas) { idea in
                    Button(idea.title) {
                        phrase = idea.phrase
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("New shortcut")
        } footer: {
            Text("Say a short phrase while dictating, and Dictate replaces it with the longer text.")
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutsSection: some View {
        Section("Shortcuts") {
            if shortcuts.isEmpty {
                Text("No shortcuts yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shortcuts) { shortcut in
                HStack(spacing: 8) {
                    Text(shortcut.phrase)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(shortcut.expansion)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Delete", systemImage: "minus.circle", role: .destructive) {
                        delete(shortcut)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete")
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { delete(shortcut) }
                }
            }
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
        modelContext.delete(shortcut)
        try? modelContext.save()
    }
}
