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
    private var mainWindow: NSWindow?

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

    func openMainWindow() {
        // A menu-bar-only app never becomes the active app, so keystrokes never arrive.
        // A normal policy while this window is open lets it take focus and record shortcuts.
        NSApp.setActivationPolicy(.regular)
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictate"
        window.backgroundColor = .white
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.contentViewController = NSHostingController(
            rootView: MainView().modelContainer(modelContainer)
        )
        window.minSize = NSSize(width: 880, height: 680)
        let defaultSize = NSSize(width: 1000, height: 860)
        window.setContentSize(defaultSize)
        DispatchQueue.main.async {
            let size = window.contentRect(forFrameRect: window.frame).size
            if size.width < defaultSize.width - 8 || size.height < defaultSize.height - 8 {
                window.setContentSize(defaultSize)
            }
        }
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        return window
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
