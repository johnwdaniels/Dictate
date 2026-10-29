import SwiftUI

/// What changed in each version, newest first, from the notes bundled with the app.
struct ReleaseNotesView: View {
    private let notes = ReleaseNote.bundled()

    private var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        if notes.isEmpty {
            ContentUnavailableView("No Release Notes", systemImage: "sparkles")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(notes) { note in
                        release(note)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func release(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Version \(note.version)")
                    .font(.title2.weight(.semibold))
                if note.version == installedVersion {
                    Text("Installed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.gradient, in: Capsule())
                }
            }
            ForEach(note.blocks.indices, id: \.self) { index in
                block(note.blocks[index])
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func block(_ block: ReleaseNote.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(Self.inline(items[index]))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
