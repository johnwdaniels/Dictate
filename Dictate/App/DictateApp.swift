import AppKit
import SwiftUI

@main
struct DictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Open Dictate") {
                appDelegate.openMainWindow()
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
        Window("Dictate", id: AppDelegate.mainWindowID) {
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
        Label("Dictate", systemImage: "mic")
            .onAppear {
                appDelegate.register(openWindow: openWindow)
            }
    }
}
