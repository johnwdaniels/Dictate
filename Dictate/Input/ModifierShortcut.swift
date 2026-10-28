import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// A right-side modifier key used on its own as a shortcut, such as Right Option.
///
/// `KeyboardShortcuts` registers Carbon hotkeys, which always need a key, so a lone modifier is watched here instead.
/// Only right-side keys are offered: the left ones start everyday shortcuts like ⌘C.
enum ModifierKey: String, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case rightControl
    case rightShift

    var keyCode: Int {
        switch self {
        case .rightOption: kVK_RightOption
        case .rightCommand: kVK_RightCommand
        case .rightControl: kVK_RightControl
        case .rightShift: kVK_RightShift
        }
    }

    var title: String {
        switch self {
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        case .rightShift: "Right ⇧ Shift"
        }
    }

    /// The device bit that says this physical key is down. The plain `.option` flag cannot tell left from right.
    private var deviceMask: UInt {
        switch self {
        case .rightOption: 0x0000_0040
        case .rightCommand: 0x0000_0010
        case .rightControl: 0x0000_2000
        case .rightShift: 0x0000_0004
        }
    }

    init?(keyCode: Int) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    func isDown(flags: UInt) -> Bool {
        flags & deviceMask != 0
    }

    /// Left-side modifiers, which the recorder turns down with a hint.
    static let leftKeyCodes: Set<Int> = [kVK_Option, kVK_Command, kVK_Control, kVK_Shift]

    // MARK: Storage

    private static func storageKey(for name: KeyboardShortcuts.Name) -> String {
        "modifierShortcut.\(name.rawValue)"
    }

    static func stored(for name: KeyboardShortcuts.Name, in defaults: UserDefaults = .standard) -> ModifierKey? {
        defaults.string(forKey: storageKey(for: name)).flatMap(ModifierKey.init(rawValue:))
    }

    static func store(_ key: ModifierKey?, for name: KeyboardShortcuts.Name, in defaults: UserDefaults = .standard) {
        if let key {
            defaults.set(key.rawValue, forKey: storageKey(for: name))
        } else {
            defaults.removeObject(forKey: storageKey(for: name))
        }
    }
}

/// Turns presses of one modifier into shortcut presses and releases.
///
/// Any other key while the modifier is held, before the hold delay, means the person is typing a chord such as ⌥E,
/// so nothing is reported. A clean tap reports a press and a release together when the key comes up.
struct ModifierTapTracker {
    enum Output: Equatable {
        case pressed(Date)
        case released(Date)
    }

    /// Long enough that a quick ⌥ chord never starts a dictation, short enough not to feel slow.
    static let holdDelay: TimeInterval = 0.15

    private var downAt: Date?
    private var chorded = false
    private var announced = false

    var isHeld: Bool { downAt != nil }

    mutating func modifierDown(at time: Date) {
        downAt = time
        chorded = false
        announced = false
    }

    mutating func otherInput() {
        guard downAt != nil, !announced else { return }
        chorded = true
    }

    mutating func holdElapsed() -> [Output] {
        guard let downAt, !chorded, !announced else { return [] }
        announced = true
        return [.pressed(downAt)]
    }

    mutating func modifierUp(at time: Date) -> [Output] {
        guard let downAt else { return [] }
        let wasChorded = chorded
        let wasAnnounced = announced
        self.downAt = nil
        chorded = false
        announced = false
        if wasChorded { return [] }
        if wasAnnounced { return [.released(time)] }
        return [.pressed(downAt), .released(time)]
    }

    mutating func reset() {
        downAt = nil
        chorded = false
        announced = false
    }
}

/// Watches for the modifier saved for a shortcut name and reports presses and releases on the main thread.
@MainActor
final class ModifierShortcutMonitor {
    private let name: KeyboardShortcuts.Name
    private let onPress: (Date) -> Void
    private let onRelease: (Date) -> Void
    private var tracker = ModifierTapTracker()
    private var heldKey: ModifierKey?
    private var holdTimer: DispatchWorkItem?
    private var monitors: [Any] = []

    init(name: KeyboardShortcuts.Name, onPress: @escaping (Date) -> Void, onRelease: @escaping (Date) -> Void) {
        self.name = name
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        guard monitors.isEmpty else { return }
        // The global monitor needs Accessibility, which dictation already asks for. The local one covers Dictate's own window.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            let input = ModifierInput(event)
            MainActor.assumeIsolated { self?.handle(input) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            let input = ModifierInput(event)
            MainActor.assumeIsolated { self?.handle(input) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ input: ModifierInput) {
        guard let key = ModifierKey.stored(for: name) else {
            if tracker.isHeld { cancelHold() }
            return
        }
        if input.isFlagsChange, input.keyCode == key.keyCode {
            let down = key.isDown(flags: input.flags)
            if down, heldKey == nil {
                heldKey = key
                tracker.modifierDown(at: input.time)
                scheduleHold()
            } else if !down, heldKey == key {
                heldKey = nil
                holdTimer?.cancel()
                emit(tracker.modifierUp(at: input.time))
            }
        } else if heldKey != nil {
            tracker.otherInput()
        }
    }

    private func scheduleHold() {
        holdTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.emit(self.tracker.holdElapsed())
            }
        }
        holdTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ModifierTapTracker.holdDelay, execute: work)
    }

    private func cancelHold() {
        holdTimer?.cancel()
        heldKey = nil
        tracker.reset()
    }

    private func emit(_ outputs: [ModifierTapTracker.Output]) {
        for output in outputs {
            switch output {
            case .pressed(let time): onPress(time)
            case .released(let time): onRelease(time)
            }
        }
    }
}

/// The parts of a key event the monitors need, copied so they can cross to the main actor.
struct ModifierInput: Sendable {
    let isFlagsChange: Bool
    let keyCode: Int
    let flags: UInt
    let time: Date

    init(_ event: NSEvent) {
        isFlagsChange = event.type == .flagsChanged
        keyCode = Int(event.keyCode)
        flags = event.modifierFlags.rawValue
        time = Date()
    }
}
