import AppKit
import SwiftUI

@main
struct DictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Open Dictator") {
                appDelegate.openMainWindow()
            }
            Button("Paste Last Dictation") {
                // The keystroke would reach the menu while it is still closing.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    appDelegate.dictationController.pasteLastDictation()
                }
            }
            Button("Check for Updates…") {
                AppUpdater.shared.checkForUpdates()
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            MenuBarIcon(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)

        // SwiftUI owns this window, so the sidebar, toolbar, and title bar get the system layout and Liquid Glass.
        Window("Dictator", id: AppDelegate.mainWindowID) {
            MainView()
                .modelContainer(appDelegate.modelContainer)
                .onDisappear(perform: appDelegate.mainWindowClosed)
        }
        .defaultSize(width: 1000, height: 860)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}

/// The menu bar icon is on screen from launch, so it hands the window opener to the app delegate.
private struct MenuBarIcon: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("Dictator", systemImage: "mic")
            .onAppear {
                appDelegate.register(openWindow: openWindow)
            }
    }
}
