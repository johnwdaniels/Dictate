import Foundation

/// Streams 16 kHz mono LINEAR16 audio to Inworld speech-to-text.
///
/// Socket work runs on this actor, off the main thread. Callbacks are invoked there too.
/// A dropped socket calls `onError` and does not crash.
actor InworldSTTClient {
    private var onInterim: @Sendable (String) -> Void = { _ in }
    private var onFinal: @Sendable (String) -> Void = { _ in }
    private var onComplete: @Sendable (String) -> Void = { _ in }
    private var onError: @Sendable (Error) -> Void = { _ in }

    func setHandlers(
        onInterim: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.onInterim = onInterim
        self.onFinal = onFinal
        self.onComplete = onComplete
        self.onError = onError
    }

    private(set) var finishedByTimeout = false

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var sessionID = UUID()
    private var phase: Phase = .idle
    private var committed = ""
    private var endContinuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private enum Phase {
        case idle
        case streaming
        case closing
        case finished
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isStreaming: Bool {
        phase == .streaming
    }

    func start(apiKey: String, language: String?, prompts: [String]) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw InworldSTTError.missingAPIKey
        }
        guard let url = InworldSTTMessages.endpoint else {
            throw InworldSTTError.invalidEndpoint
        }
        let config = try InworldSTTMessages.startMessage(language: language, prompts: prompts)
        #if DEBUG
        print("[InworldSTT] start \(config)")
        #endif

        retireCurrentSocket()

        let sessionID = UUID()
        self.sessionID = sessionID
        committed = ""
        finishedByTimeout = false
        phase = .streaming

        var request = URLRequest(url: url)
        request.setValue(InworldSTTMessages.authorizationValue(apiKey: trimmedKey), forHTTPHeaderField: "Authorization")

        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        do {
            try await socket.send(.string(config))
        } catch {
            phase = .finished
            teardownSocket()
            throw error
        }

        Task { [weak self] in
            await self?.receiveLoop(sessionID: sessionID)
        }
    }

    func sendAudio(_ pcm: Data) async {
        guard phase == .streaming, let socket, !pcm.isEmpty else { return }
        do {
            try await socket.send(.data(pcm))
        } catch {
            fail(error, sessionID: sessionID)
        }
    }

    /// Closes the socket immediately. Safe to call after `stop` or when `start` never connected.
    func cancel() {
        guard phase == .streaming || phase == .closing || socket != nil else { return }
        retireCurrentSocket()
    }

    /// Sends `{"closeStream":{}}` once. Returns when usage arrives, shortly after the last final, or after four seconds.
    func stop() async {
        guard phase == .streaming, let socket else { return }
        phase = .closing
        do {
            try await socket.send(.string(InworldSTTMessages.closeStream))
        } catch {
            fail(error, sessionID: sessionID)
            return
        }
        await waitForShutdown()
    }

    private func receiveLoop(sessionID: UUID) async {
        guard let socket else { return }
        while sessionID == self.sessionID {
            do {
                let message = try await socket.receive()
                guard sessionID == self.sessionID else { return }
                handle(message, sessionID: sessionID)
            } catch {
                guard sessionID == self.sessionID else { return }
                if phase == .closing {
                    complete(timedOut: false, sessionID: sessionID)
                } else if phase == .streaming {
                    fail(InworldSTTError.connectionLost(error.localizedDescription), sessionID: sessionID)
                }
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, sessionID: UUID) {
        let text: String?
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8)
        @unknown default:
            text = nil
        }
        guard let text else { return }

        switch InworldSTTMessages.parse(text) {
        case .interim(let transcript):
            onInterim(transcript)
        case .final(let transcript):
            committed = InworldSTTMessages.appending(committed, transcript)
            onFinal(transcript)
            scheduleSettleIfClosing(sessionID: sessionID)
        case .diagnostic(let name):
            logDiagnostic(name, raw: text)
            if name == "usage" {
                completeIfClosing(sessionID: sessionID)
            }
        case .serverError(let message):
            let error: InworldSTTError = DictationFailure.looksLikeRejectedKey(message)
                ? .rejectedKey
                : .server(message)
            fail(error, sessionID: sessionID)
        case .ignored:
            break
        }
    }

    private func waitForShutdown() async {
        if phase == .finished { return }
        timeoutTask?.cancel()
        let sessionID = self.sessionID
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.finishIfStillClosing(sessionID: sessionID)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if self.phase == .finished {
                continuation.resume()
                return
            }
            self.endContinuation = continuation
        }
    }

    /// A final ends a turn, not the socket. While shutting down, paste shortly after the last final instead of waiting for the connection to drop.
    private func scheduleSettleIfClosing(sessionID: UUID) {
        guard phase == .closing else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.completeIfClosing(sessionID: sessionID)
        }
    }

    private func completeIfClosing(sessionID: UUID) {
        guard sessionID == self.sessionID, phase == .closing else { return }
        complete(timedOut: false, sessionID: sessionID)
    }

    private func finishIfStillClosing(sessionID: UUID) {
        guard sessionID == self.sessionID, phase == .closing else { return }
        complete(timedOut: true, sessionID: sessionID)
    }

    private func complete(timedOut: Bool, sessionID: UUID) {
        guard sessionID == self.sessionID, phase != .finished else { return }
        phase = .finished
        finishedByTimeout = timedOut
        let text = committed
        teardownSocket()
        onComplete(text)
    }

    private func fail(_ error: Error, sessionID: UUID) {
        guard sessionID == self.sessionID, phase != .finished else { return }
        phase = .finished
        teardownSocket()
        onError(error)
    }

    private func retireCurrentSocket() {
        sessionID = UUID()
        phase = .finished
        teardownSocket()
    }

    private func teardownSocket() {
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        let continuation = endContinuation
        endContinuation = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        continuation?.resume()
    }

    private func logDiagnostic(_ name: String, raw: String) {
        #if DEBUG
        print("[InworldSTT] \(name) \(raw)")
        #endif
    }
}
