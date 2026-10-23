import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryTerm.createdAt, order: .forward) private var terms: [DictionaryTerm]
    @Query(sort: \DictionaryReplacement.createdAt, order: .forward) private var replacements: [DictionaryReplacement]

    @State private var draft = ""
    @State private var termSelection: UUID?
    @State private var findDraft = ""
    @State private var replaceDraft = ""
    @State private var replacementSelection: UUID?
    @State private var importNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            termEditor
            termList
            Divider()
            replacementEditor
            replacementList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var termEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These terms bias recognition toward names and jargon. It is a soft bias, not a guaranteed match.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Name or jargon", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(!canAddTerm)
            }

            if let termIssue {
                Text(termIssue)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let cleanTitle = DictionaryTermRules.cleanTitle(for: draft) {
                Button(cleanTitle) {
                    draft = DictionaryTermRules.cleaned(draft)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                Text("\(terms.count) / \(DictionaryTermRules.maximum)")
                    .foregroundStyle(terms.count >= DictionaryTermRules.maximum ? Color.red : Color.secondary)
                Spacer()
                Button("Import", action: chooseImportFile)
            }
            .font(.callout)

            if !importNote.isEmpty {
                Text(importNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var termList: some View {
        if terms.isEmpty {
            Text("No terms yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $termSelection) {
                ForEach(orderedTerms) { term in
                    Text(term.term)
                        .tag(term.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(term) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) { delete(term) }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onDeleteCommand(perform: deleteSelectedTerm)
            .onChange(of: termSelection) { _, newValue in
                if newValue != nil { replacementSelection = nil }
            }
        }
    }

    private var replacementEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replacements")
                .font(.headline)
            Text("Applied after transcription. Matching ignores case.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Find", text: $findDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReplacement)
                Text("→")
                    .foregroundStyle(.secondary)
                TextField("Replace with", text: $replaceDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReplacement)
                Button("Add", action: addReplacement)
                    .disabled(!canAddReplacement)
            }

            if let replacementIssue {
                Text(replacementIssue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var replacementList: some View {
        if replacements.isEmpty {
            Text("No replacements yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
        } else {
            List(selection: $replacementSelection) {
                ForEach(orderedReplacements) { rule in
                    Text(rowTitle(rule))
                        .tag(rule.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(rule) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) { delete(rule) }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140, maxHeight: 200)
            .onDeleteCommand(perform: deleteSelectedReplacement)
            .onChange(of: replacementSelection) { _, newValue in
                if newValue != nil { termSelection = nil }
            }
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
        if termSelection == term.id { termSelection = nil }
        modelContext.delete(term)
        try? modelContext.save()
    }

    private func deleteSelectedTerm() {
        guard let termSelection, let term = terms.first(where: { $0.id == termSelection }) else { return }
        delete(term)
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
        if replacementSelection == rule.id { replacementSelection = nil }
        modelContext.delete(rule)
        try? modelContext.save()
    }

    private func deleteSelectedReplacement() {
        guard let replacementSelection, let rule = replacements.first(where: { $0.id == replacementSelection }) else { return }
        delete(rule)
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
