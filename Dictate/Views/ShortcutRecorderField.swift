import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// Records the dictation shortcut without using `KeyboardShortcuts.Recorder`.
///
/// That control is an `NSSearchField` that only listens while it is first responder.
/// In this accessory window the field loses focus as soon as it is cleared, so a new
/// shortcut can never be captured. This view listens from a click until a key is chosen.
struct ShortcutRecorderField: NSViewRepresentable {
    var name: KeyboardShortcuts.Name = .startDictation

    func makeNSView(context: Context) -> ShortcutRecorderBox {
        ShortcutRecorderBox(name: name)
    }

    func updateNSView(_ nsView: ShortcutRecorderBox, context: Context) {
        nsView.refreshIfIdle()
    }

    static func dismantleNSView(_ nsView: ShortcutRecorderBox, coordinator: ()) {
        nsView.cancelIfRecording()
    }
}

final class ShortcutRecorderBox: NSStackView {
    private let name: KeyboardShortcuts.Name
    private let recordButton = NSButton()
    private let clearButton = NSButton()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isRecording = false
    private var shortcutBeforeRecording: KeyboardShortcuts.Shortcut?
    private var rejectionTask: Task<Void, Never>?

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 24))

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        detachesHiddenViews = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)

        recordButton.bezelStyle = .rounded
        recordButton.setButtonType(.momentaryPushIn)
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.sendAction(on: [.leftMouseDown])
        recordButton.font = .systemFont(ofSize: NSFont.systemFontSize)
        recordButton.title = "Record shortcut"
        recordButton.toolTip = "Click, then press a shortcut that includes Command, Option, or Control."
        recordButton.setAccessibilityLabel("Dictation shortcut")
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        addArrangedSubview(recordButton)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.toolTip = "Clear shortcut"
        clearButton.setAccessibilityLabel("Clear shortcut")
        addArrangedSubview(clearButton)

        Task { @MainActor in
            self.refreshIfIdle()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: clearButton.isHidden ? 150 : 176, height: 24)
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }

    func refreshIfIdle() {
        guard !isRecording else { return }
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        recordButton.title = shortcut?.description ?? "Record shortcut"
        recordButton.bezelColor = nil
        clearButton.isHidden = shortcut == nil
        invalidateIntrinsicContentSize()
    }

    func cancelIfRecording() {
        guard isRecording else { return }
        cancel()
    }

    @objc private func toggleRecording() {
        MainActor.assumeIsolated {
            if isRecording {
                cancel()
            } else {
                begin()
            }
        }
    }

    @objc private func clearShortcut() {
        MainActor.assumeIsolated {
            rejectionTask?.cancel()
            stopMonitor()
            isRecording = false
            shortcutBeforeRecording = nil
            KeyboardShortcuts.setShortcut(nil, for: name)
            refreshIfIdle()
        }
    }

    private func begin() {
        rejectionTask?.cancel()
        shortcutBeforeRecording = KeyboardShortcuts.getShortcut(for: name)
        // Unregister first so the current hotkey cannot swallow the combination being recorded.
        KeyboardShortcuts.setShortcut(nil, for: name)
        isRecording = true
        recordButton.title = "Press shortcut"
        recordButton.bezelColor = .controlAccentColor
        clearButton.isHidden = true
        invalidateIntrinsicContentSize()
        bringAppForward()
        installMonitor()
    }

    private func cancel() {
        rejectionTask?.cancel()
        stopMonitor()
        isRecording = false
        KeyboardShortcuts.setShortcut(shortcutBeforeRecording, for: name)
        shortcutBeforeRecording = nil
        refreshIfIdle()
    }

    private func commit(_ shortcut: KeyboardShortcuts.Shortcut) {
        rejectionTask?.cancel()
        stopMonitor()
        isRecording = false
        shortcutBeforeRecording = nil
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        refreshIfIdle()
    }

    private func bringAppForward() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.receive(KeyPress(event))
        }
        // Keys often stay with the previously active app. A global monitor still sees them.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            let press = KeyPress(event)
            MainActor.assumeIsolated {
                self.handle(press)
            }
        }
        if globalMonitor == nil {
            promptForAccessibility()
            recordButton.title = "Allow Accessibility"
        }
    }

    private func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func receive(_ press: KeyPress) -> NSEvent? {
        MainActor.assumeIsolated {
            handle(press)
        }
        return nil
    }

    private func stopMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ press: KeyPress) {
        guard isRecording, !press.isRepeat else { return }

        if !press.hasNonShiftModifier {
            if press.isEscape {
                cancel()
                return
            }
            if press.isDelete {
                clearShortcut()
                return
            }
        }

        guard press.hasNonShiftModifier || press.isFunctionKey else {
            reject("Needs ⌘, ⌥, or ⌃")
            return
        }

        // Match KeyboardShortcuts.Shortcut(event:): keep the key code and drop the Fn bit.
        let shortcut = KeyboardShortcuts.Shortcut(
            carbonKeyCode: press.keyCode,
            carbonModifiers: press.carbonModifiers
        )

        if shortcut.isTakenBySystem {
            reject("Used by the system")
            return
        }

        if menuOwns(shortcut) {
            reject("Used by a menu")
            return
        }

        commit(shortcut)
    }

    private func reject(_ message: String) {
        NSSound.beep()
        recordButton.title = message
        rejectionTask?.cancel()
        rejectionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, self.isRecording else { return }
            self.recordButton.title = "Press shortcut"
        }
    }

    private func menuOwns(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        return menuContains(menu, shortcut: shortcut)
    }

    private func menuContains(_ menu: NSMenu, shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        for item in menu.items {
            if itemMatches(item, shortcut: shortcut) {
                return true
            }
            if let submenu = item.submenu, menuContains(submenu, shortcut: shortcut) {
                return true
            }
        }
        return false
    }

    private func itemMatches(_ item: NSMenuItem, shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var keyEquivalent = item.keyEquivalent
        guard !keyEquivalent.isEmpty else { return false }

        var mask = item.keyEquivalentModifierMask
        if shortcut.modifiers.contains(.shift), keyEquivalent.lowercased() != keyEquivalent {
            keyEquivalent = keyEquivalent.lowercased()
            mask.insert(.shift)
        }

        return shortcut.nsMenuItemKeyEquivalent == keyEquivalent && shortcut.modifiers == mask
    }
}

private struct KeyPress: Sendable {
    let keyCode: Int
    let carbonModifiers: Int
    let isRepeat: Bool
    let isFunctionKey: Bool
    let isEscape: Bool
    let isDelete: Bool
    let hasNonShiftModifier: Bool

    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.control) { carbon |= controlKey }

        keyCode = Int(event.keyCode)
        carbonModifiers = carbon
        isRepeat = event.isARepeat
        isEscape = keyCode == kVK_Escape
        isDelete = keyCode == kVK_Delete
        hasNonShiftModifier = !flags.intersection([.command, .option, .control]).isEmpty
        switch event.specialKey {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
             .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            isFunctionKey = true
        default:
            isFunctionKey = false
        }
    }
}
