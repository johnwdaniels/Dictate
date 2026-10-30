import SwiftUI

struct MainView: View {
    enum Page: String, CaseIterable, Identifiable {
        case history = "History"
        case dictionary = "Dictionary"
        case shortcuts = "Shortcuts"
        case insights = "Insights"
        case settings = "Settings"
        case releaseNotes = "Release Notes"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .history: "clock"
            case .dictionary: "character.book.closed"
            case .shortcuts: "bolt"
            case .insights: "chart.bar"
            case .settings: "gearshape"
            case .releaseNotes: "sparkles"
            }
        }

        var blurb: String {
            switch self {
            case .history: "Everything you have dictated"
            case .dictionary: "Names, jargon, and replacements"
            case .shortcuts: "Phrases that expand as you speak"
            case .insights: "Time saved and words dictated"
            case .settings: "Shortcut, key, and permissions"
            case .releaseNotes: "What changed in each version"
            }
        }

        static let library: [Page] = [.history, .dictionary, .shortcuts, .insights]
        static let app: [Page] = [.settings, .releaseNotes]
    }

    @State private var selection: Page? = .history
    @State private var showOnboarding = false

    private var page: Page { selection ?? .history }

    var body: some View {
        // A native split view gets the floating glass sidebar and toolbar on macOS 26 and later.
        NavigationSplitView {
            sidebar
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(page.rawValue)
                .navigationSubtitle(page.blurb)
        }
        .glassWindow()
        .frame(
            minWidth: 880,
            idealWidth: 1000,
            maxWidth: .infinity,
            minHeight: 680,
            idealHeight: 860,
            maxHeight: .infinity
        )
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
        List(selection: $selection) {
            Section {
                ForEach(Page.library) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            Section("App") {
                ForEach(Page.app) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            brand
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(DictateChrome.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Dictate")
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
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
        case .releaseNotes:
            ReleaseNotesView()
        }
    }
}

/// The brand gradient now appears only on the app mark.
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
