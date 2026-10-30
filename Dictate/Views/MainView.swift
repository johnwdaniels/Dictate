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
            SidebarBrand()
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
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

/// The app's name at the top of the sidebar, with the icon picked in Settings.
struct SidebarBrand: View {
    @AppStorage(AppIconChoice.storageKey) private var appIcon = AppIconChoice.fallback.rawValue

    var body: some View {
        HStack(spacing: 8) {
            // The icon art has a transparent margin, so it is drawn larger and pulled in to sit like a 24-point badge.
            Image((AppIconChoice(rawValue: appIcon) ?? AppIconChoice.fallback).imageName)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .padding(-3)
            Text("Dictator")
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
