import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static let needsRestartNote = "Turn Dictate on, then quit and reopen. macOS applies Accessibility the next time Dictate starts. If the list already shows Dictate on, the switch belongs to an earlier copy: click Reset Accessibility, turn Dictate on again, then quit and reopen."

    private static var relaunching = false

    /// Clears Dictate's Accessibility entry, then asks again. A switch left over from an earlier copy shows as on but
    /// does not apply to this one, and only a fresh entry fixes that.
    static func resetAndAsk() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", identifier]
        try? task.run()
        task.waitUntilExit()
        prompt()
        NSWorkspace.shared.open(SystemSettingsLink.accessibility)
    }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Quits this process, then opens the same app once. macOS only reports Accessibility for a process that launched after the switch was turned on.
    @MainActor
    static func quitAndReopen() {
        guard !relaunching else { return }
        relaunching = true
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = shellQuote(Bundle.main.bundlePath)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictate-relaunch-\(pid).sh")
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do
          sleep 0.1
        done
        open -- \(bundlePath)
        rm -f \(shellQuote(scriptURL.path))
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "nohup \(shellQuote(scriptURL.path)) >/dev/null 2>&1 &"]
            try task.run()
        } catch {
            relaunching = false
            return
        }
        NSApp.terminate(nil)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
