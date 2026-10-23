import Foundation
import KeyboardShortcuts
import UserNotifications

enum DictationListenMode: String, CaseIterable, Identifiable {
    case holdToTalk
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk: "Hold to talk"
        case .toggle: "Toggle"
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
    private let notices = DictationNoticePresenter()

    func startMonitoringShortcut() {
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated {
                self?.indicator?.updateLevel(level)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .startDictation) { [weak self] in
            Task { @MainActor in
                self?.shortcutPressed()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .startDictation) { [weak self] in
            Task { @MainActor in
                self?.shortcutReleased()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .openRecording) { [weak self] in
            Task { @MainActor in
                self?.openRecordingPressed()
            }
        }
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

    private func shortcutPressed() {
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
        }
    }

    private func shortcutReleased() {
        guard DictationListenMode.current == .holdToTalk else { return }
        guard phase == .recording else { return }
        requestStop()
    }

    private func begin() {
        guard phase == .idle else { return }
        phase = .recording
        stopRequested = false
        recordingStartedAt = nil
        recordingStoppedAt = nil
        interimText = ""
        generation = UUID()
        let generation = generation
        let recorder = recorder
        let client = client

        Task.detached { [weak self] in
            await self?.runSession(generation: generation, recorder: recorder, client: client)
        }
    }

    private func requestStop() {
        guard phase == .recording else { return }
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
        client: InworldSTTClient
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
            onFinal: { _ in },
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
            await MainActor.run {
                guard self.generation == generation, self.phase == .recording else { return }
                if self.recordingStartedAt == nil {
                    self.recordingStartedAt = Date()
                }
                self.indicator?.dictationDidStart()
            }
            var sentAudio = false
            for await chunk in stream {
                sentAudio = true
                await client.sendAudio(chunk)
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

        await recorder.stopAndWait()
        if startedSocket {
            await client.stop()
            outcome.setTimedOut(await client.finishedByTimeout)
            await client.cancel()
        }
        await MainActor.run { self.deliver(outcome.snapshot(), generation: generation) }
    }

    private func shouldStop(_ generation: UUID) -> Bool {
        self.generation != generation || stopRequested || phase != .recording
    }

    private func publishInterim(_ text: String, generation: UUID) {
        guard self.generation == generation, phase == .recording || phase == .processing else { return }
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
        let transcript = (dictionary?.applyReplacements(to: raw) ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            report(DictationFailure.emptyTranscript)
            return
        }
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
            let target = FrontmostAppTracker.shared.target()
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
