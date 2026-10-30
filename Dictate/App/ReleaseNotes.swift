import Foundation

/// One release's notes, read from the `release-notes/<tag>.md` file bundled with the app.
struct ReleaseNote: Identifiable, Equatable {
    enum Block: Equatable {
        case paragraph(String)
        case bullets([String])
    }

    /// The version without its "v", such as "1.5.5".
    let version: String
    let blocks: [Block]

    var id: String { version }

    /// Every bundled release, newest first.
    static func bundled(in bundle: Bundle = .main) -> [ReleaseNote] {
        let urls = bundle.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
        return urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("v"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return ReleaseNote(version: String(name.dropFirst()), markdown: text)
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    init(version: String, blocks: [Block]) {
        self.version = version
        self.blocks = blocks
    }

    /// Splits the notes into paragraphs and bullet lists. Inline Markdown such as **bold** stays in the text.
    init(version: String, markdown: String) {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if !bullets.isEmpty {
                blocks.append(.bullets(bullets))
                bullets = []
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
            } else {
                if !bullets.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        self.init(version: version, blocks: blocks)
    }
}
