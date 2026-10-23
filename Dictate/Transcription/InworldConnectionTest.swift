import Foundation

/// Opens the speech-to-text socket, sends the config and `closeStream`, and does not record audio.
enum InworldConnectionTest {
    static func check(apiKey: String, language: String?) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InworldSTTError.missingAPIKey
        }
        guard let url = InworldSTTMessages.endpoint else {
            throw InworldSTTError.invalidEndpoint
        }
        let config = try InworldSTTMessages.startMessage(language: language, prompts: [])
        var request = URLRequest(url: url)
        request.setValue(InworldSTTMessages.authorizationValue(apiKey: trimmed), forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        do {
            try await socket.send(.string(config))
            try await socket.send(.string(InworldSTTMessages.closeStream))
            try await watch(socket, key: trimmed)
        } catch let error as InworldSTTError {
            throw error
        } catch {
            let redacted = redacting(error.localizedDescription, key: trimmed)
            if DictationFailure.looksLikeRejectedKey(error) || DictationFailure.looksLikeRejectedKey(redacted) {
                throw InworldSTTError.rejectedKey
            }
            throw InworldSTTError.connectionLost(redacted)
        }
    }

    private static func watch(_ socket: URLSessionWebSocketTask, key: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if Task.isCancelled { return }
                    guard let text = text(from: message) else { continue }
                    if case .serverError(let serverMessage) = InworldSTTMessages.parse(text) {
                        let cleaned = redacting(serverMessage, key: key)
                        if DictationFailure.looksLikeRejectedKey(cleaned) {
                            throw InworldSTTError.rejectedKey
                        }
                        throw InworldSTTError.server(cleaned)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
            }
            do {
                try await group.next()
            } catch {
                group.cancelAll()
                try? await drain(group)
                if error is InworldSTTError || !isBenignClose(error) {
                    throw error
                }
                return
            }
            group.cancelAll()
            try? await drain(group)
        }
    }

    private static func drain(_ group: ThrowingTaskGroup<Void, Error>) async throws {
        for try await _ in group {}
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

    private static func isBenignClose(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 { return true }
        if let urlError = error as? URLError, urlError.code == .networkConnectionLost || urlError.code == .cancelled {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("socket is not connected")
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
