import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings section that sets a writing style for each group of apps.
struct StyleSection: View {
    @State private var styles = Dictionary(uniqueKeysWithValues: AppCategory.allCases.map { ($0, AppStyle.style(for: $0)) })
    @State private var apps = Dictionary(uniqueKeysWithValues: AppCategory.allCases.map { ($0, AppStyle.bundleIDs(for: $0)) })

    var body: some View {
        Section("Style") {
            ForEach(AppCategory.allCases) { category in
                row(category)
            }
        }
    }

    private func row(_ category: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.body.weight(.medium))
                    Text("“\(AppStyle.apply(style(category), to: AppStyle.sample))”")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Picker(category.title, selection: styleBinding(category)) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if category == .other {
                Text("Every app not listed above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 72), alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(apps[category] ?? [], id: \.self) { bundleID in
                        AppTile(bundleID: bundleID) {
                            AppStyle.remove(bundleID, from: category)
                            reload()
                        }
                    }
                    AddAppTile {
                        add(to: category)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func style(_ category: AppCategory) -> WritingStyle {
        styles[category] ?? category.defaultStyle
    }

    private func styleBinding(_ category: AppCategory) -> Binding<WritingStyle> {
        Binding {
            style(category)
        } set: { style in
            UserDefaults.standard.set(style.rawValue, forKey: category.styleKey)
            styles[category] = style
        }
    }

    private func add(to category: AppCategory) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            AppStyle.move(bundleID, to: category)
        }
        reload()
    }

    private func reload() {
        for category in AppCategory.allCases {
            apps[category] = AppStyle.bundleIDs(for: category)
        }
    }
}

private struct AppTile: View {
    let bundleID: String
    let remove: () -> Void

    private var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var name: String {
        if let url {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return AppStyle.knownNames[bundleID] ?? bundleID
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .padding(3)
                }
            }
            .frame(width: 40, height: 40)
            Text(name)
                .font(.caption)
                .foregroundStyle(url == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 64)
        .help(url == nil ? "\(name) is not installed" : name)
        .contextMenu {
            Button("Remove \(name)", action: remove)
        }
    }
}

private struct AddAppTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.tertiary)
                    .overlay {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                Text("Add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add an app")
    }
}
