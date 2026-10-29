import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PastePreferences {
    static let clickAtMouseKey = "paste.clickAtMousePosition"
    static let trailingSpaceKey = "paste.addTrailingSpace"

    static var clickAtMousePosition: Bool {
        UserDefaults.standard.bool(forKey: clickAtMouseKey)
    }

    /// Missing key means on, matching the Settings toggle's default.
    static var addTrailingSpace: Bool {
        guard UserDefaults.standard.object(forKey: trailingSpaceKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: trailingSpaceKey)
    }

    static func insertionText(from transcript: String) -> String {
        addTrailingSpace ? transcript + " " : transcript
    }
}

enum PasteServiceError: LocalizedError {
    case accessibilityDenied
    case pasteboardFailed
    case eventFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            DictationFailure.accessibilityDenied
        case .pasteboardFailed:
            "Dictate could not put the transcript on the clipboard."
        case .eventFailed:
            "Dictate could not send the paste keystroke."
        }
    }
}

/// Inserts text into the focused text field by pasting, then puts the clipboard back.
@MainActor
enum PasteService {
    static func paste(_ text: String) async throws {
        try ensureTrusted()

        let snapshot = PasteboardSnapshot.capture()
        do {
            if PastePreferences.clickAtMousePosition {
                try postClick(at: screenPoint(fromCocoa: NSEvent.mouseLocation))
                try await Task.sleep(for: .milliseconds(100))
            }
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            try writeToPasteboard(SmartSpacing.prepare(text, bundleID: bundleID))
            try postCommandV()
            try await Task.sleep(for: .milliseconds(150))
            snapshot.restore()
        } catch {
            try? await Task.sleep(for: .milliseconds(150))
            snapshot.restore()
            throw error
        }
    }

    private static func ensureTrusted() throws {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw PasteServiceError.accessibilityDenied
        }
    }

    private static func writeToPasteboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteServiceError.pasteboardFailed
        }
    }

    private static func postCommandV() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            throw PasteServiceError.eventFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private static func postClick(at point: CGPoint) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            throw PasteServiceError.eventFailed
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// `NSEvent.mouseLocation` uses the bottom-left of the main display. `CGEvent` uses the top-left.
    static func screenPoint(fromCocoa point: NSPoint) -> CGPoint {
        let primary = NSScreen.screens.first { $0.frame.contains(CGPoint(x: 0, y: 0)) } ?? NSScreen.screens.first
        let top = primary?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: top - point.y)
    }
}

private struct PasteboardSnapshot {
    struct Item {
        var payloads: [(NSPasteboard.PasteboardType, Payload)]
    }

    enum Payload {
        case data(Data)
        case string(String)
    }

    var items: [Item]

    static func capture() -> PasteboardSnapshot {
        let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Item(payloads: item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, .data(data))
                }
                if let string = item.string(forType: type) {
                    return (type, .string(string))
                }
                return nil
            })
        }
        return PasteboardSnapshot(items: saved)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { saved in
            let item = NSPasteboardItem()
            for (type, payload) in saved.payloads {
                switch payload {
                case .data(let data):
                    item.setData(data, forType: type)
                case .string(let string):
                    item.setString(string, forType: type)
                }
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
