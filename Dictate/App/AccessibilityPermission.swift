import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static let needsRestartNote = "Turn Dictate on, then quit and reopen. macOS applies Accessibility the next time Dictate starts. If Dictate is already on after an update, remove it with − and add it again, since the switch belongs to the earlier version."

    private static var relaunching = false

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
