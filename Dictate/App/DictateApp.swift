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
            Label("Dictate", systemImage: "mic")
        }
        .menuBarExtraStyle(.menu)
    }
}
