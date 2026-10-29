import Foundation
import os

/// Opens the speech-to-text socket, sends the config, a moment of silence and `closeStream`, and waits for Inworld to
/// answer. It does not record audio.
enum InworldConnectionTest {
    static func check(apiKey: String, language: String?) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InworldSTTError.missingAPIKey
        }
        guard let url = InworldSTTMessages.endpoint else {
            throw InworldSTTError.invalidEndpoint
        }
        let models = InworldModelMemory.order(for: trimmed)
        var lastError: Error = InworldSTTError.server("The transcription model is unavailable.")
        for (index, model) in models.enumerated() {
            do {
                try await probe(apiKey: trimmed, language: language, modelId: model, url: url)
                InworldModelMemory.remember(model, for: trimmed)
                return
            } catch {
                lastError = error
                let message = (error as? InworldSTTError).flatMap { detail in
                    if case .server(let text) = detail { return text }
                    return nil
                } ?? ""
                if index + 1 < models.count, DictationFailure.looksLikeUnavailableModel(message) {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    /// A healthy session answers this much silence with usage in well under a second.
    static let probeAudio = Data(count: 3_200)
    static let replyWait = Duration.seconds(5)

    private static func probe(apiKey: String, language: String?, modelId: String, url: URL) async throws {
        let config = try InworldSTTMessages.startMessage(language: language, prompts: [], modelId: modelId)
        var request = URLRequest(url: url)
        request.setValue(InworldSTTMessages.authorizationValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        // Neither `send` nor `receive` notices task cancellation, so the deadline closes the socket to end them.
        let expired = OSAllocatedUnfairLock(initialState: false)
        let deadline = Task {
            try await Task.sleep(for: replyWait)
            expired.withLock { $0 = true }
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            deadline.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        do {
            // Listen before sending. A refused key is answered with an error and a close that can beat the probe audio,
            // and the error is lost if nothing is reading yet.
            async let reply: Void = awaitReply(socket, key: apiKey)
            do {
                try await socket.send(.string(config))
                try await socket.send(.data(probeAudio))
                try await socket.send(.string(InworldSTTMessages.closeStream))
            } catch {
                try await reply
                throw error
            }
            try await reply
            DictateLog.connection.info("Test connection: \(modelId, privacy: .public) answered")
        } catch let error as InworldSTTError {
            DictateLog.connection.error("Test connection: \(modelId, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        } catch {
            let redacted = redacting(error.localizedDescription, key: apiKey)
            if expired.withLock({ $0 }) {
                DictateLog.connection.error("Test connection: no reply from Inworld within \(replyWait.components.seconds)s")
                throw InworldSTTError.unreachable
            }
            DictateLog.connection.error("Test connection: \(redacted, privacy: .public)")
            if DictationFailure.looksLikeRejectedKey(error) || DictationFailure.looksLikeRejectedKey(redacted) {
                throw InworldSTTError.rejectedKey
            }
            throw InworldSTTError.connectionLost(redacted)
        }
    }

    /// Returns at the first answer to the probe audio. A server error is thrown as the reason.
    private static func awaitReply(_ socket: URLSessionWebSocketTask, key: String) async throws {
        while true {
            let message = try await socket.receive()
            guard let text = text(from: message) else { continue }
            switch InworldSTTMessages.parse(text) {
            case .serverError(let serverMessage):
                let cleaned = redacting(serverMessage, key: key)
                if DictationFailure.looksLikeUnavailableModel(cleaned) {
                    throw InworldSTTError.server(cleaned)
                }
                if DictationFailure.looksLikeRejectedKey(cleaned) {
                    throw InworldSTTError.rejectedKey
                }
                throw InworldSTTError.server(cleaned)
            case .interim, .final, .diagnostic:
                return
            case .ignored:
                continue
            }
        }
    }

    private static func text(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let value):
            return value
        case .data(let data):
            return String(data: data, encoding: .utf8)
        @unknown default:
            return nil
        }
    }

    /// Removes the key if a transport error quotes it back. The key is never written to a log.
    private static func redacting(_ message: String, key: String) -> String {
        var result = message
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.replacingOccurrences(of: trimmed, with: "[key]")
            let authorization = InworldSTTMessages.authorizationValue(apiKey: trimmed)
            if authorization != trimmed {
                result = result.replacingOccurrences(of: authorization, with: "[key]")
            }
        }
        return result
    }
}
