import AppKit
import SwiftUI

/// A small non-activating pill above the Dock. It never becomes key and ignores clicks.
@MainActor
final class FloatingIndicator: NSObject, FloatingDictationIndicator {
    static let visibilityKey = "indicator.hidden"
    /// Missing key means on: the pill shows the words as they are heard.
    static let liveTextKey = "indicator.showLiveText"

    private let panel: IndicatorPanel
    private let model = IndicatorModel()
    private var hideTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    override init() {
        // Room for the widest pill plus 20 points around it for the glass shadow.
        panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 76))
        super.init()
        let hosting = ClearHostingView(rootView: FloatingIndicatorPill(model: model))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        observePreferences()
    }

    func dictationDidStart() {
        guard isEnabled else { return }
        hideTask?.cancel()
        model.interim = ""
        model.message = ""
        model.resetLevels()
        model.phase = .recording
        reveal()
    }

    func updateInterimText(_ text: String) {
        guard isEnabled, model.phase == .recording else { return }
        model.interim = text
    }

    func updateLevel(_ level: Float) {
        guard isEnabled, model.phase == .recording else { return }
        model.push(level)
    }

    func dictationDidStartProcessing() {
        guard isEnabled, model.phase == .recording || model.phase == .processing else { return }
        guard panel.isVisible || model.phase == .recording else { return }
        hideTask?.cancel()
        model.phase = .processing
        reveal()
    }

    func dictationDidSucceed() {
        guard isEnabled else { return }
        hideTask?.cancel()
        model.phase = .success
        reveal()
        scheduleDismiss(after: 0.6)
    }

    func dictationDidFail(_ message: String) {
        guard isEnabled else { return }
        hideTask?.cancel()
        model.message = Self.short(message)
        model.phase = .failure
        reveal()
        scheduleDismiss(after: 2)
    }

    func dictationDidCancel() {
        guard panel.isVisible else { return }
        scheduleDismiss(after: 0)
    }

    private var isEnabled: Bool {
        !UserDefaults.standard.bool(forKey: Self.visibilityKey)
    }

    private func reveal() {
        position()
        let fadingIn = !panel.isVisible || panel.alphaValue < 0.01
        panel.orderFrontRegardless()
        model.presented = true
        if #available(macOS 26, *) {
            panel.alphaValue = 1
        } else if fadingIn {
            panel.alphaValue = 0
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.18
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            NSAnimationContext.endGrouping()
        } else {
            panel.alphaValue = 1
        }
    }

    private func scheduleDismiss(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            model.presented = false
            if #available(macOS 26, *) {
                // Let the glass dissolve before the window goes.
                try? await Task.sleep(for: .milliseconds(380))
            } else {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.2
                NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                NSAnimationContext.endGrouping()
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled, !model.presented else { return }
            panel.orderOut(nil)
            model.phase = .idle
        }
    }

    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 2
        ))
    }

    private func observePreferences() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `MainActor.assumeIsolated` faults on macOS 26 when AppKit delivers this on the main thread. Hop instead.
            Task { @MainActor in
                self?.hideIfDisabled()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                self.position()
            }
        }
    }

    private func hideIfDisabled() {
        guard !isEnabled else { return }
        hideTask?.cancel()
        model.presented = false
        model.phase = .idle
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private static func short(_ message: String) -> String {
        let line = message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard line.count > 64 else { return line.isEmpty ? "Something went wrong." : line }
        return String(line.prefix(63)) + "…"
    }
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
}

private final class IndicatorPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class IndicatorModel: ObservableObject {
    static let barCount = 9

    @Published var phase: IndicatorPhase = .idle
    @Published var presented = false
    @Published var interim = ""
    @Published var message = ""
    @Published var levels = Array(repeating: CGFloat(0.08), count: IndicatorModel.barCount)

    func resetLevels() {
        levels = Array(repeating: 0.08, count: Self.barCount)
    }

    func push(_ level: Float) {
        var next = levels
        next.removeFirst()
        next.append(CGFloat(min(1, max(0, level))))
        levels = next
    }
}

private enum IndicatorPhase: Equatable {
    case idle
    case recording
    case processing
    case success
    case failure
}

private struct FloatingIndicatorPill: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                LiquidGlassPill(model: model)
            } else {
                FlatPill(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// macOS 26 and later. A glass bubble holds the status; a glass capsule flows out of it for the words. Both sit in one
/// container, so they merge and split like liquid, and the glass materializes in and dissolves out.
@available(macOS 26, *)
private struct LiquidGlassPill: View {
    @ObservedObject var model: IndicatorModel
    @AppStorage(FloatingIndicator.liveTextKey) private var showLiveText = true
    @Namespace private var glass

    private var words: String? {
        switch model.phase {
        case .recording: showLiveText && !model.interim.isEmpty ? model.interim : nil
        case .failure: model.message
        default: nil
        }
    }

    private var tint: Color? {
        model.phase == .failure ? Color.red.opacity(0.5) : nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if model.presented {
                HStack(spacing: 6) {
                    PillStatus(model: model)
                        .frame(width: 36, height: 36)
                        .glassEffect(.clear.tint(tint), in: Circle())
                        .glassEffectID("status", in: glass)
                        .glassEffectTransition(.materialize)
                    if let words {
                        Text(words)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(model.phase == .failure ? .tail : .head)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .frame(maxWidth: 300, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .glassEffect(.clear.tint(tint), in: Capsule())
                            .glassEffectID("words", in: glass)
                            .glassEffectTransition(.matchedGeometry)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.presented)
        .animation(.smooth(duration: 0.3), value: words == nil)
        .animation(.smooth(duration: 0.25), value: model.phase)
        .animation(.easeOut(duration: 0.12), value: model.levels)
    }
}

/// The waveform, spinner, check or warning, in the glass's own vibrant color.
@available(macOS 26, *)
private struct PillStatus: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .recording, .idle:
                HStack(alignment: .center, spacing: 2) {
                    ForEach(model.levels.indices.suffix(5), id: \.self) { index in
                        Capsule()
                            .frame(width: 2.5, height: 3 + model.levels[index] * 14)
                    }
                }
                .foregroundStyle(.primary)
                .transition(.blurReplace)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .transition(.blurReplace)
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .transition(.blurReplace)
            case .failure:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .transition(.blurReplace)
            }
        }
    }
}

/// Before macOS 26: the flat capsule with a hairline edge.
private struct FlatPill: View {
    @ObservedObject var model: IndicatorModel
    @AppStorage(FloatingIndicator.liveTextKey) private var showLiveText = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            if model.phase == .processing || model.phase == .success {
                Spacer(minLength: 0)
            }
            status
            if model.phase == .recording, showLiveText, !model.interim.isEmpty {
                Text(model.interim)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(foreground.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.phase == .failure {
                Text(model.message)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(foreground.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.phase == .processing || model.phase == .success {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 232, height: 36)
        .background(fill, in: Capsule())
        .overlay {
            Capsule().strokeBorder(foreground.opacity(0.08), lineWidth: 1)
        }
        .scaleEffect(model.presented ? 1 : 0.94)
        .animation(.easeOut(duration: 0.18), value: model.presented)
        .animation(.easeOut(duration: 0.12), value: model.levels)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .recording, .idle:
            waveform
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(foreground.opacity(0.7))
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground.opacity(0.85))
        case .failure:
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground.opacity(0.9))
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(model.levels.indices, id: \.self) { index in
                Capsule()
                    .fill(foreground.opacity(0.78))
                    .frame(width: 2.5, height: 3 + model.levels[index] * 14)
            }
        }
        .frame(width: 42, height: 18)
    }

    private var fill: Color {
        if model.phase == .failure {
            return colorScheme == .dark
                ? Color(red: 0.42, green: 0.16, blue: 0.15).opacity(0.94)
                : Color(red: 0.62, green: 0.28, blue: 0.26).opacity(0.94)
        }
        return colorScheme == .dark
            ? Color.black.opacity(0.62)
            : Color.white.opacity(0.78)
    }

    private var foreground: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.82)
    }
}
