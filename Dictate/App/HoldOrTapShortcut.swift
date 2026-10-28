import Foundation

/// Decides what the shortcut does in Hold or tap mode. A quick tap keeps the recording open until the next press. A longer hold stops when the keys are released.
struct HoldOrTapShortcut {
    enum Action: Equatable {
        case start
        case stop
        case nothing
    }

    /// Presses shorter than this count as a tap.
    static let holdThreshold: TimeInterval = 0.4

    private var pressStartedAt: Date?

    mutating func pressed(at now: Date, phase: DictationPhase) -> Action {
        switch phase {
        case .idle:
            pressStartedAt = now
            return .start
        case .recording:
            pressStartedAt = nil
            return .stop
        case .processing:
            pressStartedAt = nil
            return .nothing
        }
    }

    mutating func released(at now: Date, phase: DictationPhase) -> Action {
        guard let start = pressStartedAt else { return .nothing }
        pressStartedAt = nil
        guard phase == .recording else { return .nothing }
        return now.timeIntervalSince(start) >= Self.holdThreshold ? .stop : .nothing
    }
}
