import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryTerm.createdAt, order: .forward) private var terms: [DictionaryTerm]
    @Query(sort: \DictionaryReplacement.createdAt, order: .forward) private var replacements: [DictionaryReplacement]

    @State private var draft = ""
    @State private var findDraft = ""
    @State private var replaceDraft = ""
    @State private var importNote = ""

    var body: some View {
        Form {
            termsSection
            replacementsSection
        }
        .glassForm()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import", systemImage: "square.and.arrow.down", action: chooseImportFile)
                    .help("Import terms from a text file, one per line")
            }
        }
    }

    private var termsSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Add a term", text: $draft, prompt: Text("Name or jargon"))
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(!canAddTerm)
            }
            if let termIssue {
                Text(termIssue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let cleanTitle = DictionaryTermRules.cleanTitle(for: draft) {
                Button(cleanTitle) {
                    draft = DictionaryTermRules.cleaned(draft)
                }
                .buttonStyle(.borderless)
            }
            if !importNote.isEmpty {
                Text(importNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if terms.isEmpty {
                Text("No terms yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(orderedTerms) { term in
                row(term.term) { delete(term) }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Terms")
                Spacer()
                Text("\(terms.count) of \(DictionaryTermRules.maximum)")
                    .monospacedDigit()
                    .foregroundStyle(terms.count >= DictionaryTermRules.maximum ? Color.red : Color.secondary)
            }
        } footer: {
            Text("These terms bias recognition toward names and jargon. It is a soft bias, not a guaranteed match.")
                .foregroundStyle(.secondary)
        }
    }

    private var replacementsSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Find", text: $findDraft, prompt: Text("Word or phrase"))
                    .onSubmit(addReplacement)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Replace with", text: $replaceDraft, prompt: Text("Replace with"))
                    .labelsHidden()
                    .onSubmit(addReplacement)
                Button("Add", action: addReplacement)
                    .disabled(!canAddReplacement)
            }
            if let replacementIssue {
                Text(replacementIssue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if replacements.isEmpty {
                Text("No replacements yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(orderedReplacements) { rule in
                row(rowTitle(rule)) { delete(rule) }
            }
        } header: {
            Text("Replacements")
        } footer: {
            Text("Applied after transcription. Matching ignores case.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, delete: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Delete", systemImage: "minus.circle", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete")
        }
        .contextMenu {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var orderedTerms: [DictionaryTerm] {
        terms.sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    private var orderedReplacements: [DictionaryReplacement] {
        replacements.sorted { $0.find.localizedStandardCompare($1.find) == .orderedAscending }
    }

    private var existingTerms: [String] {
        terms.map(\.term)
    }

    private var existingFinds: [String] {
        replacements.map(\.find)
    }

    private var termIssue: String? {
        DictionaryTermRules.issue(for: draft, existing: existingTerms, count: terms.count)
    }

    private var canAddTerm: Bool {
        DictionaryTermRules.canAdd(draft, existing: existingTerms, count: terms.count)
    }

    private var replacementIssue: String? {
        DictionaryReplacements.issue(for: findDraft, existing: existingFinds)
    }

    private var canAddReplacement: Bool {
        DictionaryReplacements.canAdd(find: findDraft, existing: existingFinds)
    }

    private func addTerm() {
        let term = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DictionaryTermRules.canAdd(term, existing: existingTerms, count: terms.count) else { return }
        modelContext.insert(DictionaryTerm(term: term))
        try? modelContext.save()
        draft = ""
        importNote = ""
    }

    private func delete(_ term: DictionaryTerm) {
        modelContext.delete(term)
        try? modelContext.save()
    }

    private func addReplacement() {
        let find = findDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DictionaryReplacements.canAdd(find: find, existing: existingFinds) else { return }
        let replacement = replaceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(DictionaryReplacement(find: find, replacement: replacement))
        try? modelContext.save()
        findDraft = ""
        replaceDraft = ""
    }

    private func delete(_ rule: DictionaryReplacement) {
        modelContext.delete(rule)
        try? modelContext.save()
    }

    private func rowTitle(_ rule: DictionaryReplacement) -> String {
        let target = rule.replacement.isEmpty ? "nothing" : rule.replacement
        return "\(rule.find) → \(target)"
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Dictionary Terms"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTerms(from: url)
    }

    private func importTerms(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard var text = try? String(contentsOf: url, encoding: .utf8) else {
            importNote = "That file couldn't be read as text."
            return
        }
        if text.hasPrefix("\u{feff}") {
            text.removeFirst()
        }
        let plan = DictionaryTermRules.planImport(text: text, existing: existingTerms)
        for term in plan.accepted {
            modelContext.insert(DictionaryTerm(term: term))
        }
        if !plan.accepted.isEmpty {
            try? modelContext.save()
        }
        importNote = plan.summary
    }
}
