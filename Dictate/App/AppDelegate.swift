import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dictationController: DictationController
    let modelContainer: ModelContainer
    private let historyStore: DictationHistoryStore
    private let dictionaryStore: DictionaryStore
    private let floatingIndicator: FloatingIndicator
    private var openWindow: OpenWindowAction?
    private var openWhenReady = false

    static let mainWindowID = "main"

    override init() {
        let container = Self.makeModelContainer()
        modelContainer = container
        let store = DictationHistoryStore(container: container)
        historyStore = store
        let dictionary = DictionaryStore(container: container)
        dictionaryStore = dictionary
        let indicator = FloatingIndicator()
        floatingIndicator = indicator
        let controller = DictationController()
        controller.history = store
        controller.dictionary = dictionary
        controller.indicator = indicator
        dictationController = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.accessory)
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        FrontmostAppTracker.shared.start()
        dictationController.startMonitoringShortcut()
        if !UserDefaults.standard.bool(forKey: Onboarding.completeKey) {
            openMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again from Finder, the Dock, or `open` shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    /// The menu bar icon may appear before or after launch finishes, so a request made first waits for it.
    func register(openWindow action: OpenWindowAction) {
        openWindow = action
        if openWhenReady {
            openWhenReady = false
            openMainWindow()
        }
    }

    func openMainWindow() {
        guard let openWindow else {
            openWhenReady = true
            return
        }
        // A menu-bar-only app never becomes the active app, so keystrokes never arrive.
        // A normal policy while this window is open lets it take focus and record shortcuts.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: Self.mainWindowID)
        NSApp.activate()
    }

    func mainWindowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: DictationEntry.self,
                DictionaryTerm.self,
                DictionaryReplacement.self,
                SpokenShortcut.self
            )
        } catch {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(
                for: DictationEntry.self,
                DictionaryTerm.self,
                DictionaryReplacement.self,
                SpokenShortcut.self,
                configurations: configuration
            )
        }
    }
}
