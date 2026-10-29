import AppKit

/// Remembers the last app that was not Dictate, so a paste can be attributed after this window is in front.
@MainActor
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()

    private var lastOther: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
        note(NSWorkspace.shared.frontmostApplication)
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.note(app)
            }
        }
    }

    func target() -> (name: String, bundleID: String)? {
        let front = NSWorkspace.shared.frontmostApplication
        let chosen = isDictate(front) ? lastOther : front
        guard let chosen, !isDictate(chosen) else { return nil }
        let name = chosen.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return (name, chosen.bundleIdentifier ?? "")
    }

    /// The process of the app being dictated into, for reading its window.
    func targetProcessID() -> pid_t? {
        let front = NSWorkspace.shared.frontmostApplication
        let chosen = isDictate(front) ? lastOther : front
        guard let chosen, !isDictate(chosen) else { return nil }
        return chosen.processIdentifier
    }

    private func note(_ app: NSRunningApplication?) {
        guard let app, !isDictate(app) else { return }
        lastOther = app
    }

    private func isDictate(_ app: NSRunningApplication?) -> Bool {
        guard let identifier = app?.bundleIdentifier else { return false }
        return identifier == Bundle.main.bundleIdentifier
    }
}
