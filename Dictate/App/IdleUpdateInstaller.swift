import AppKit
import CoreGraphics
import Sparkle

/// Installs an update Sparkle downloaded in the background once nobody has touched the Mac for a few minutes, instead of
/// waiting for Dictate to quit. Dictate rarely quits, so without this an update would sit until the next restart.
@MainActor
final class IdleUpdateInstaller: NSObject, SPUUpdaterDelegate {
    static let idleSeconds: TimeInterval = 180
    private static let checkInterval: TimeInterval = 30

    /// True while a dictation is recording or processing. An update never interrupts one.
    var isBusy: () -> Bool = { false }

    private var install: (() -> Void)?
    private var timer: Timer?

    static func shouldInstall(idleSeconds idle: TimeInterval, busy: Bool) -> Bool {
        !busy && idle >= idleSeconds
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        install = immediateInstallHandler
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.installIfIdle()
            }
        }
        // Sparkle still installs on quit if the Mac is never idle long enough.
        return true
    }

    private func installIfIdle() {
        guard Self.shouldInstall(idleSeconds: Self.secondsSinceLastInput(), busy: isBusy()),
              let install else { return }
        timer?.invalidate()
        timer = nil
        self.install = nil
        // Quits, swaps in the new version, and reopens Dictate.
        install()
    }

    private static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
