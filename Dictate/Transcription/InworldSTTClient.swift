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
    /// Whether Inworld sent anything at all on the current socket. Silence from the server is a network problem.
    private(set) var heardFromServer = false

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var sessionID = UUID()
    private var phase: Phase = .idle
    private var committed = ""
    private var sessionKey = ""
    private var prompts: [String] = []
    /// Words that arrive while the socket connects, such as names read from the screen.
    private var morePrompts: (@Sendable () async -> [String])?
    private var endContinuation: CheckedContinuation<Void, Never>?
    private var startupContinuation: CheckedContinuation<StartupResult, Never>?
    private var pendingStartupError: Error?
    private var timeoutTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private enum Phase {
        case idle
        case starting
        case streaming
        case closing
        case finished
    }

    private enum StartupResult {
        case ready
        case failed(Error)
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isStreaming: Bool {
        phase == .streaming
    }

    /// `morePrompts` is awaited after the socket starts connecting, so it overlaps the handshake.
    func start(
        apiKey: String,
        language: String?,
        prompts: [String],
        morePrompts: (@Sendable () async -> [String])? = nil
    ) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw InworldSTTError.missingAPIKey
        }
        guard InworldSTTMessages.endpoint != nil else {
            throw InworldSTTError.invalidEndpoint
        }

        sessionKey = trimmedKey
        self.prompts = prompts
        self.morePrompts = morePrompts
        let remembered = InworldModelMemory.remembered(for: trimmedKey)
        let models = InworldModelMemory.order(for: trimmedKey)
        var lastError: Error = InworldSTTError.server("The transcription model is unavailable.")

        for (index, model) in models.enumerated() {
            try await openSocket(apiKey: trimmedKey, language: language, modelId: model)
            if let pendingStartupError {
                let error = pendingStartupError
                self.pendingStartupError = nil
                lastError = error
                if canTryNextModel(error, index: index, count: models.count) {
                    continue
                }
                throw error
            }
            if remembered == model {
                phase = .streaming
                InworldModelMemory.remember(model, for: trimmedKey)
                return
            }

            switch await waitForAcceptance() {
            case .ready:
                InworldModelMemory.remember(model, for: trimmedKey)
                return
            case .failed(let error):
                lastError = error
                if canTryNextModel(error, index: index, count: models.count) {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func openSocket(apiKey: String, language: String?, modelId: String) async throws {
        guard let url = InworldSTTMessages.endpoint else {
            throw InworldSTTError.invalidEndpoint
        }

        retireCurrentSocket()
        pendingStartupError = nil

        let sessionID = UUID()
        self.sessionID = sessionID
        committed = ""
        finishedByTimeout = false
        heardFromServer = false
        phase = .starting

        var request = URLRequest(url: url)
        request.setValue(InworldSTTMessages.authorizationValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        // The handshake is under way, so waiting for these words here costs little or nothing.
        if let morePrompts {
            self.morePrompts = nil
            prompts = Self.merged(prompts, await morePrompts())
        }

        do {
            let config = try InworldSTTMessages.startMessage(language: language, prompts: prompts, modelId: modelId)
            #if DEBUG
            print("[InworldSTT] start \(config)")
            #endif
            DictateLog.connection.info(
                "Session start: \(modelId, privacy: .public), language \(language ?? "auto", privacy: .public), \(self.prompts.count) prompts"
            )
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

    /// Dictionary words first, then the rest, without repeats, up to the dictionary's own limit.
    static func merged(_ first: [String], _ more: [String]) -> [String] {
        var seen = Set(first.map { $0.lowercased() })
        var result = first
        for term in more where result.count < DictionaryTermRules.maximum && seen.insert(term.lowercased()).inserted {
            result.append(term)
        }
        return result
    }

    /// A refused model comes back quickly. Silence means the config was accepted, so audio can start.
    private func waitForAcceptance() async -> StartupResult {
        if let pendingStartupError {
            self.pendingStartupError = nil
            return .failed(pendingStartupError)
        }
        let sessionID = self.sessionID
        return await withCheckedContinuation { continuation in
            startupContinuation = continuation
            startupTimeoutTask?.cancel()
            startupTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await self?.startupTimedOut(sessionID: sessionID)
            }
        }
    }

    private func startupTimedOut(sessionID: UUID) {
        guard sessionID == self.sessionID, phase == .starting else { return }
        finishStartup(.ready, sessionID: sessionID)
    }

    private func finishStartup(_ result: StartupResult, sessionID: UUID) {
        guard sessionID == self.sessionID, let continuation = startupContinuation else { return }
        startupContinuation = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        switch result {
        case .ready:
            phase = .streaming
        case .failed:
            phase = .finished
            teardownSocket()
        }
        continuation.resume(returning: result)
    }

    private func canTryNextModel(_ error: Error, index: Int, count: Int) -> Bool {
        guard index + 1 < count, let error = error as? InworldSTTError else { return false }
        guard case .server(let message) = error else { return false }
        return DictationFailure.looksLikeUnavailableModel(message)
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
                DictateLog.connection.error(
                    "Socket ended while \(String(describing: self.phase), privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                if phase == .starting {
                    let wrapped = InworldSTTError.connectionLost(error.localizedDescription)
                    if startupContinuation != nil {
                        finishStartup(.failed(wrapped), sessionID: sessionID)
                    } else {
                        pendingStartupError = wrapped
                        phase = .finished
                        teardownSocket()
                    }
                } else if phase == .closing {
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
        heardFromServer = true

        switch InworldSTTMessages.parse(text) {
        case .interim(let transcript):
            onInterim(transcript)
        case .final(let transcript):
            let kept = PromptEchoFilter.filter(transcript, terms: prompts, isFirstSegment: committed.isEmpty)
            #if DEBUG
            if kept != transcript {
                print("[InworldSTT] dropped echoed dictionary terms: \(transcript)")
            }
            #endif
            DictateLog.connection.info("Final: \(transcript.count) characters, \(kept.count) kept")
            committed = InworldSTTMessages.appending(committed, kept)
            onFinal(kept)
            scheduleSettleIfClosing(sessionID: sessionID)
        case .diagnostic(let name):
            logDiagnostic(name, raw: text)
            if name == "usage" {
                completeIfClosing(sessionID: sessionID)
            }
        case .serverError(let message):
            DictateLog.connection.error("Server error: \(DictationFailure.serverMessage(message), privacy: .public)")
            let error: InworldSTTError = DictationFailure.looksLikeRejectedKey(message)
                ? .rejectedKey
                : .server(message)
            if phase == .starting {
                if startupContinuation != nil {
                    finishStartup(.failed(error), sessionID: sessionID)
                } else {
                    pendingStartupError = error
                    phase = .finished
                    teardownSocket()
                }
                return
            }
            if case .server(let text) = error, DictationFailure.looksLikeUnavailableModel(text) {
                InworldModelMemory.forget(sessionKey)
            }
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
        DictateLog.connection.info(
            "Session end: \(text.count) characters, heard from server \(self.heardFromServer), timed out \(timedOut)"
        )
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
        let continuation = startupContinuation
        startupContinuation = nil
        sessionID = UUID()
        phase = .finished
        pendingStartupError = nil
        teardownSocket()
        continuation?.resume(returning: .failed(InworldSTTError.connectionLost("The connection dropped.")))
    }

    private func teardownSocket() {
        timeoutTask?.cancel()
        timeoutTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        let continuation = endContinuation
        endContinuation = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        continuation?.resume()
    }

    private func logDiagnostic(_ name: String, raw: String) {
        // Usage carries how much audio Inworld received, which tells a dead microphone from a dead connection.
        if name == "usage" {
            DictateLog.connection.info("Usage: \(raw, privacy: .public)")
        } else {
            DictateLog.connection.debug("\(name, privacy: .public)")
        }
        #if DEBUG
        print("[InworldSTT] \(name) \(raw)")
        #endif
    }
}
