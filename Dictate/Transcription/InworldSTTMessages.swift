import Foundation

enum InworldSTTError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidEndpoint
    case invalidConfiguration
    case microphoneDenied
    case audioFormatUnavailable
    case connectionLost(String)
    case unreachable
    case rejectedKey
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return DictationFailure.missingKey
        case .invalidEndpoint:
            return "The speech service address is invalid."
        case .invalidConfiguration:
            return "The transcription session could not be configured."
        case .microphoneDenied:
            return DictationFailure.microphoneDenied
        case .audioFormatUnavailable:
            return "The microphone format is unavailable."
        case .connectionLost:
            return DictationFailure.connectionDropped
        case .unreachable:
            return DictationFailure.unreachable
        case .rejectedKey:
            return DictationFailure.rejectedKey
        case .server(let message):
            return DictationFailure.serverMessage(message)
        }
    }
}

enum InworldServerEvent: Equatable {
    case interim(String)
    case final(String)
    case diagnostic(String)
    case serverError(String)
    case ignored
}

enum InworldSTTMessages {
    static let endpoint = URL(string: "wss://api.inworld.ai/stt/v1/transcribe:streamBidirectional")
    static let closeStream = #"{"closeStream":{}}"#

    static func authorizationValue(apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("basic ") {
            return trimmed
        }
        return "Basic \(trimmed)"
    }

    /// Language values that mean auto-detect are omitted from the config.
    static func languageCode(_ language: String?) -> String? {
        guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let automatic = ["auto", "auto-detect", "autodetect"]
        if automatic.contains(trimmed.lowercased()) {
            return nil
        }
        return trimmed
    }

    /// `prompts` is a field of `transcribeConfig`. It is left out when empty.
    static func startMessage(language: String?, prompts: [String], modelId: String) throws -> String {
        let terms = prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let payload = StartMessage(
            transcribeConfig: TranscribeConfig(
                modelId: modelId,
                language: languageCode(language),
                prompts: terms.isEmpty ? nil : terms
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw InworldSTTError.invalidConfiguration
        }
        return text
    }

    static func parse(_ text: String) -> InworldServerEvent {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored
        }

        if let message = serverErrorMessage(in: object) {
            return .serverError(message)
        }

        guard let result = object["result"] as? [String: Any] else {
            return .ignored
        }

        if let transcription = result["transcription"] as? [String: Any] {
            let transcript = transcription["transcript"] as? String ?? ""
            if bool(transcription["isFinal"]) {
                return .final(transcript)
            }
            return .interim(transcript)
        }

        if result["speechStarted"] != nil {
            return .diagnostic("speechStarted")
        }
        if result["speechStopped"] != nil {
            return .diagnostic("speechStopped")
        }
        if result["usage"] != nil {
            return .diagnostic("usage")
        }
        return .ignored
    }

    static func appending(_ committed: String, _ segment: String) -> String {
        guard !segment.isEmpty else { return committed }
        guard !committed.isEmpty else { return segment }
        if committed.last?.isWhitespace == true || segment.first?.isWhitespace == true {
            return committed + segment
        }
        return committed + " " + segment
    }

    private static func serverErrorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status = (error["status"] as? String) ?? ""
            let code = error["code"].map { String(describing: $0) } ?? ""
            let detail = [status, code].filter { !$0.isEmpty }.joined(separator: " ")
            if message.isEmpty && detail.isEmpty {
                return "The transcription service rejected the session."
            }
            if message.isEmpty { return detail }
            if detail.isEmpty { return message }
            return message + "\n" + detail
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if object["code"] != nil, let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    private struct TranscribeConfig: Encodable {
        var modelId: String
        var audioEncoding = "LINEAR16"
        var sampleRateHertz = 16000
        var numberOfChannels = 1
        var language: String?
        var prompts: [String]?
        /// Lower than the server default so a pause finalizes sooner. Hold-to-talk still joins every final into one paste.
        var endOfTurnConfidenceThreshold = 0.4
        var inworldSttV1Config = InworldSttV1Config(
            minEndOfTurnSilenceWhenConfident: 288,
            maxTurnSilence: 480
        )
    }

    private struct InworldSttV1Config: Encodable {
        var minEndOfTurnSilenceWhenConfident: Int
        var maxTurnSilence: Int
    }

    private struct StartMessage: Encodable {
        var transcribeConfig: TranscribeConfig
        var audioProtocol = "BINARY"
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }
}
