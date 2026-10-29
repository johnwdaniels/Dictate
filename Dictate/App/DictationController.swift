import Foundation
import KeyboardShortcuts
import UserNotifications

enum DictationListenMode: String, CaseIterable, Identifiable {
    case holdToTalk
    case toggle
    case holdOrTap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk: "Hold to talk"
        case .toggle: "Toggle"
        case .holdOrTap: "Hold or tap"
        }
    }

    static let storageKey = "dictationListenMode"

    static var current: DictationListenMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? DictationListenMode.holdToTalk.rawValue
        return DictationListenMode(rawValue: raw) ?? .holdToTalk
    }
}

enum DictationPhase: Equatable {
    case idle
    case recording
    case processing
}

/// Prompt 4 pastes the finished transcript.
@MainActor
protocol DictationPasting: AnyObject {
    func paste(_ text: String)
}

/// Stores a finished transcript.
@MainActor
protocol DictationHistorySaving: AnyObject {
    func saveToHistory(
        _ text: String,
        durationSeconds: Double,
        appName: String,
        bundleID: String
    ) throws
}

/// The floating pill. It must not activate the app or take keyboard focus.
@MainActor
protocol FloatingDictationIndicator: AnyObject {
    func dictationDidStart()
    func updateInterimText(_ text: String)
    func updateLevel(_ level: Float)
    func dictationDidStartProcessing()
    func dictationDidSucceed()
    func dictationDidFail(_ message: String)
    func dictationDidCancel()
}

/// Starts and stops dictation from the global shortcut.
@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var interimText = ""
    @Published private(set) var phase: DictationPhase = .idle

    weak var paster: DictationPasting?
    weak var history: DictationHistorySaving?
    weak var dictionary: DictationDictionary?
    weak var indicator: FloatingDictationIndicator?

    private let recorder = AudioRecorder()
    private let client = InworldSTTClient()
    private var generation = UUID()
    private var stopRequested = false
    private var recordingStartedAt: Date?
    private var recordingStoppedAt: Date?
    private var holdOrTap = HoldOrTapShortcut()
    private var modifierMonitors: [ModifierShortcutMonitor] = []
    /// True between a right-side modifier going down and the press being confirmed. The mic and connection are already
    /// starting, but nothing has been played or shown yet.
    private var armedSession = false
    private var gate = StartGate()
    private var liveTranscript = LiveTranscript()
    private let notices = DictationNoticePresenter()

    func startMonitoringShortcut() {
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated {
                self?.indicator?.updateLevel(level)
            }
        }
        // The time is read here, before the hop to the main actor, so a tap is not mistaken for a hold.
        KeyboardShortcuts.onKeyDown(for: .startDictation) { [weak self] in
            let now = Date()
            Task { @MainActor in
                self?.shortcutPressed(at: now)
            }
        }
        KeyboardShortcuts.onKeyUp(for: .startDictation) { [weak self] in
            let now = Date()
            Task { @MainActor in
                self?.shortcutReleased(at: now)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .openRecording) { [weak self] in
            Task { @MainActor in
                self?.openRecordingPressed()
            }
        }
        // A lone right-side modifier, such as Right Option, can be either shortcut.
        let dictationModifier = ModifierShortcutMonitor(
            name: .startDictation,
            onArm: { [weak self] time in self?.shortcutArmed(at: time) },
            onDisarm: { [weak self] in self?.cancelArmed() },
            onPress: { [weak self] time in self?.shortcutPressed(at: time) },
            onRelease: { [weak self] time in self?.shortcutReleased(at: time) }
        )
        let openRecordingModifier = ModifierShortcutMonitor(
            name: .openRecording,
            onPress: { [weak self] _ in self?.openRecordingPressed() },
            onRelease: { _ in }
        )
        dictationModifier.start()
        openRecordingModifier.start()
        modifierMonitors = [dictationModifier, openRecordingModifier]
    }

    /// Starts a recording that stays open after the keys are released. The next press stops it and pastes.
    private func openRecordingPressed() {
        switch phase {
        case .idle:
            begin()
        case .recording:
            requestStop()
        case .processing:
            return
        }
    }

    /// A right-side modifier went down. Start the mic and the connection now, quietly, so nothing said during the
    /// typing check is lost. Every mode starts from idle on a press, so this only runs from idle.
    private func shortcutArmed(at time: Date) {
        guard phase == .idle else { return }
        begin(armedAt: time)
    }

    /// The modifier was part of a chord such as ⌥E, so the quiet start is dropped without a sound or the pill.
    private func cancelArmed() {
        guard armedSession else { return }
        armedSession = false
        generation = UUID()
        phase = .idle
        gate.cancel()
        recorder.stop()
        let client = client
        Task { await client.cancel() }
    }

    private func shortcutPressed(at now: Date) {
        if armedSession {
            // The session started on key-down. Confirm it, and let Hold or tap note when the press began.
            if DictationListenMode.current == .holdOrTap {
                _ = holdOrTap.pressed(at: now, phase: .idle)
            }
            armedSession = false
            playStartCue()
            return
        }
        switch DictationListenMode.current {
        case .holdToTalk:
            guard phase == .idle else { return }
            begin()
        case .toggle:
            switch phase {
            case .idle:
                begin()
            case .recording:
                requestStop()
            case .processing:
                return
            }
        case .holdOrTap:
            perform(holdOrTap.pressed(at: now, phase: phase))
        }
    }

    private func shortcutReleased(at now: Date) {
        switch DictationListenMode.current {
        case .holdToTalk:
            guard phase == .recording else { return }
            requestStop()
        case .toggle:
            return
        case .holdOrTap:
            perform(holdOrTap.released(at: now, phase: phase))
        }
    }

    private func perform(_ action: HoldOrTapShortcut.Action) {
        switch action {
        case .start: begin()
        case .stop: requestStop()
        case .nothing: return
        }
    }

    private func begin(armedAt: Date? = nil) {
        guard phase == .idle else { return }
        phase = .recording
        stopRequested = false
        recordingStartedAt = nil
        recordingStoppedAt = nil
        interimText = ""
        liveTranscript = LiveTranscript()
        generation = UUID()
        gate = StartGate(keepFrom: armedAt?.timeIntervalSinceReferenceDate)
        armedSession = armedAt != nil
        if armedAt == nil {
            playStartCue()
        }
        let generation = generation
        let recorder = recorder
        let client = client
        let gate = gate

        Task.detached { [weak self] in
            await self?.runSession(generation: generation, recorder: recorder, client: client, gate: gate)
        }
    }

    /// The pill and the start sound come right away. The connection opens alongside them instead of before them.
    private func playStartCue() {
        recordingStartedAt = Date()
        indicator?.dictationDidStart()
        StartChime.play()
        gate.open(cue: CFAbsoluteTimeGetCurrent(), ring: StartChime.ringDuration)
    }

    private func requestStop() {
        guard phase == .recording else { return }
        armedSession = false
        phase = .processing
        stopRequested = true
        if recordingStoppedAt == nil {
            recordingStoppedAt = Date()
        }
        indicator?.dictationDidStartProcessing()
        recorder.stop()
    }

    private nonisolated func runSession(
        generation: UUID,
        recorder: AudioRecorder,
        client: InworldSTTClient,
        gate: StartGate
    ) async {
        let apiKey: String?
        let keyNotice: String?
        do {
            apiKey = try InworldAPIKeyStore.load()
            keyNotice = apiKey == nil ? DictationFailure.missingKey : nil
        } catch {
            apiKey = nil
            keyNotice = DictationFailure.message(for: error)
        }
        let shouldLeave = await MainActor.run { () -> Bool in
            guard self.generation == generation else { return true }
            if let keyNotice {
                self.abandon(generation: generation, notice: keyNotice)
                return true
            }
            if self.stopRequested {
                self.abandon(generation: generation, notice: nil)
                return true
            }
            return false
        }
        guard !shouldLeave, let apiKey else { return }

        let outcome = TranscriptOutcome()
        await client.setHandlers(
            onInterim: { [weak self] text in
                Task { @MainActor in
                    self?.publishInterim(text, generation: generation)
                }
            },
            onFinal: { [weak self] text in
                Task { @MainActor in
                    self?.publishFinal(text, generation: generation)
                }
            },
            onComplete: { text in
                outcome.setText(text)
            },
            onError: { error in
                outcome.setError(error)
                Task { await recorder.stopAndWait() }
            }
        )

        let session = await MainActor.run { () -> (prompts: [String], language: String?) in
            (self.dictionary?.promptTerms() ?? [], DictationLanguage.storedCode)
        }
        let audioTask = Task { try await recorder.start() }
        var startedSocket = false
        var audioAwaited = false
        do {
            try await client.start(apiKey: apiKey, language: session.language, prompts: session.prompts)
            startedSocket = true
            audioAwaited = true
            let stream = try await audioTask.value
            // A right-side modifier starts quietly. Wait until the press is confirmed, or turns out to be a chord.
            while gate.state == .waiting, !(await shouldStop(generation)) {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if gate.state == .cancelled {
                await stopSharedIfIdle(recorder: recorder, client: client)
                return
            }
            // The stream kept everything since the mic opened. Skip the start sound, send the rest.
            let forwardFrom = gate.forwardFrom
            var sentAudio = false
            for await chunk in stream where chunk.time >= forwardFrom {
                sentAudio = true
                await client.sendAudio(chunk.data)
            }
            if !sentAudio, await shouldStop(generation) {
                await recorder.stopAndWait()
                await client.cancel()
                await MainActor.run { self.abandon(generation: generation, notice: nil) }
                return
            }
            await MainActor.run {
                guard self.generation == generation else { return }
                if self.phase == .recording {
                    self.phase = .processing
                    self.indicator?.dictationDidStartProcessing()
                }
            }
        } catch {
            outcome.setError(error)
            if !audioAwaited {
                _ = try? await audioTask.value
            }
        }

        // A chord cancelled this session while it connected, and a newer one may own the mic and socket now.
        guard await MainActor.run(body: { self.generation == generation }) else {
            await stopSharedIfIdle(recorder: recorder, client: client)
            return
        }
        await recorder.stopAndWait()
        if startedSocket {
            await client.stop()
            outcome.setTimedOut(await client.finishedByTimeout)
            await client.cancel()
        }
        await MainActor.run { self.deliver(outcome.snapshot(), generation: generation) }
    }

    /// Stops the shared mic and socket for a cancelled session, unless a new dictation has already started on them.
    private nonisolated func stopSharedIfIdle(recorder: AudioRecorder, client: InworldSTTClient) async {
        let idle = await MainActor.run { self.phase == .idle }
        guard idle else { return }
        await recorder.stopAndWait()
        await client.cancel()
    }

    private func shouldStop(_ generation: UUID) -> Bool {
        self.generation != generation || stopRequested || phase != .recording
    }

    private func publishInterim(_ text: String, generation: UUID) {
        guard self.generation == generation, phase == .recording || phase == .processing else { return }
        show(liveTranscript.showing(partial: text))
    }

    private func publishFinal(_ text: String, generation: UUID) {
        guard self.generation == generation, phase == .recording || phase == .processing else { return }
        show(liveTranscript.finish(text))
    }

    private func show(_ text: String) {
        interimText = text
        indicator?.updateInterimText(text)
    }

    private func abandon(generation: UUID, notice: String?) {
        guard self.generation == generation else { return }
        interimText = ""
        phase = .idle
        if let notice {
            indicator?.dictationDidFail(notice)
            notices.post(notice)
        } else {
            indicator?.dictationDidCancel()
        }
    }

    private func deliver(_ outcome: (text: String?, error: Error?, timedOut: Bool), generation: UUID) {
        guard self.generation == generation else { return }
        interimText = ""
        defer { phase = .idle }

        if let error = outcome.error {
            report(DictationFailure.message(for: error))
            return
        }

        let raw = outcome.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            report(outcome.timedOut ? DictationFailure.timedOut : DictationFailure.emptyTranscript)
            return
        }
        let cleaned = TranscriptCleanup.clean(raw)
        let replaced = (dictionary?.applyReplacements(to: cleaned) ?? cleaned)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replaced.isEmpty else {
            report(DictationFailure.emptyTranscript)
            return
        }
        let target = FrontmostAppTracker.shared.target()
        let transcript = AppStyle.styled(replaced, bundleID: target?.bundleID ?? "")
        indicator?.dictationDidSucceed()
        let insertion = PastePreferences.insertionText(from: transcript)
        Task { @MainActor in
            do {
                try await PasteService.paste(insertion)
            } catch {
                let message = DictationFailure.message(for: error)
                self.notices.post(message)
                self.indicator?.dictationDidFail(message)
            }
        }
        let duration = recordingDuration()
        recordingStartedAt = nil
        recordingStoppedAt = nil
        do {
            try history?.saveToHistory(
                transcript,
                durationSeconds: duration,
                appName: target?.name ?? "",
                bundleID: target?.bundleID ?? ""
            )
        } catch {
            notices.post("Couldn't save this dictation to history.")
        }
    }

    private func report(_ message: String) {
        indicator?.dictationDidFail(message)
        notices.post(message)
    }

    private func recordingDuration() -> Double {
        guard let start = recordingStartedAt else { return 0 }
        let end = recordingStoppedAt ?? Date()
        return max(0, end.timeIntervalSince(start))
    }
}

private final class TranscriptOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    private var error: Error?
    private var timedOut = false

    func setText(_ text: String) {
        lock.lock()
        self.text = text
        lock.unlock()
    }

    func setError(_ error: Error) {
        lock.lock()
        if self.error == nil {
            self.error = error
        }
        lock.unlock()
    }

    func setTimedOut(_ timedOut: Bool) {
        lock.lock()
        self.timedOut = timedOut
        lock.unlock()
    }

    func snapshot() -> (text: String?, error: Error?, timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (text, error, timedOut)
    }
}

final class DictationNoticePresenter: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func post(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Dictate"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
