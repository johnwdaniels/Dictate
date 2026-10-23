import SwiftUI

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable {
        case history = "History"
        case dictionary = "Dictionary"
        case shortcuts = "Shortcuts"
        case insights = "Insights"
        case settings = "Settings"
        case debug = "Debug"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .history: "clock"
            case .dictionary: "character.book.closed"
            case .shortcuts: "bolt"
            case .insights: "chart.bar"
            case .settings: "gearshape"
            case .debug: "waveform"
            }
        }

        var blurb: String {
            switch self {
            case .history: "Everything you have dictated"
            case .dictionary: "Names, jargon, and replacements"
            case .shortcuts: "Phrases that expand as you speak"
            case .insights: "Time saved and words dictated"
            case .settings: "Shortcut, key, and permissions"
            case .debug: "Live transcription"
            }
        }

        static let library: [Section] = [.history, .dictionary, .shortcuts, .insights]
    }

    @State private var section: Section = .history
    @State private var showOnboarding = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .frame(
            minWidth: 880,
            idealWidth: 1000,
            maxWidth: .infinity,
            minHeight: 680,
            idealHeight: 860,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if !UserDefaults.standard.bool(forKey: Onboarding.completeKey) {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(DictateChrome.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Dictate")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ForEach(Section.library) { item in
                sidebarButton(item)
            }

            sidebarCaption("App")
            sidebarButton(.settings)
            sidebarButton(.debug)

            Spacer(minLength: 0)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
    }

    private func sidebarCaption(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func sidebarButton(_ item: Section) -> some View {
        SidebarItemButton(item: item, isSelected: section == item) {
            section = item
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(section.rawValue)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(section.blurb)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background {
            ZStack {
                DictateChrome.gradient
                RadialGradient(
                    colors: [Color.white.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 280
                )
                RadialGradient(
                    colors: [Color(red: 0.18, green: 0.38, blue: 0.92).opacity(0.45), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 320
                )
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch section {
        case .history:
            HistoryView()
        case .dictionary:
            DictionaryView()
        case .shortcuts:
            ShortcutsView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        case .debug:
            TranscriptionDebugView()
        }
    }
}

private enum DictateChrome {
    static let orange = Color(red: 0.96, green: 0.46, blue: 0.18)
    static let amber = Color(red: 0.98, green: 0.66, blue: 0.28)
    static let blue = Color(red: 0.29, green: 0.56, blue: 0.95)
    static let deepBlue = Color(red: 0.20, green: 0.40, blue: 0.90)

    static let gradient = LinearGradient(
        colors: [orange, amber, blue, deepBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct SidebarItemButton: View {
    let item: MainView.Section
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(item.rawValue, systemImage: item.systemImage)
                .font(.body.weight(isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.10) : (hovered ? Color.primary.opacity(0.05) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
