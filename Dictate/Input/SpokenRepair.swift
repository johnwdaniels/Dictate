import Foundation

/// Optional repair of a finished transcript through an Inworld chat completion.
/// Off unless the user turns it on. A failed call returns the text it was given.
enum SpokenRepair {
    static let repairKey = "cleanup.repairSpokenText"
    static let polishKey = "cleanup.polish"
    static let endpoint = URL(string: "https://api.inworld.ai/v1/chat/completions")!
    static let model = "inworld/models/gemma-4-26b-a4b-it"

    static let repairPrompt = """
        You edit a speech-to-text transcript. Return only the edited transcript.

        Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

        Fix grammar, agreement, and small words that were dropped. Fix words that are obvious mishearings from context.

        Keep the language of the transcript. Keep names, numbers, and commitments. A question stays a question. Do not answer it. Do not add information. Do not tighten or rephrase beyond what the repair needs.

        No preamble, label, or quotation marks around the result.
        """

    static let polishPrompt = """
        You edit a speech-to-text transcript. Return only the edited transcript.

        Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

        Fix grammar, agreement, small words that were dropped, and words that are obvious mishearings from context. You may tighten and rephrase.

        Keep the meaning, the language, the names, the numbers, and the commitments. A question stays a question. Do not answer it. Do not add information.

        No preamble, label, or quotation marks around the result.
        """

    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static func repairIsOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: repairKey)
    }

    /// True only when repair and polish are both on.
    static func polishIsOn(in defaults: UserDefaults = .standard) -> Bool {
        repairIsOn(in: defaults) && defaults.bool(forKey: polishKey)
    }

    static func maxTokens(for transcript: String) -> Int {
        min(4096, max(64, transcript.count / 3 + 64))
    }

    static func requestBody(transcript: String, polish: Bool) throws -> Data {
        let body = RequestBody(
            model: model,
            temperature: 0,
            stream: false,
            maxTokens: maxTokens(for: transcript),
            messages: [
                Message(role: "system", content: polish ? polishPrompt : repairPrompt),
                Message(role: "user", content: transcript),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    /// The repaired text, or nil when the reply should be discarded.
    static func acceptedText(from data: Data, status: Int, input: String) -> String? {
        guard status == 200,
              let reply = try? JSONDecoder().decode(ChatCompletion.self, from: data),
              let choice = reply.choices.first,
              choice.finishReason != "length",
              let content = choice.message.content else { return nil }
        let cleaned = strippingOneQuotePair(content.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count <= max(input.count * 2, input.count + 80) else { return nil }
        return cleaned
    }

    static func apply(
        _ transcript: String,
        defaults: UserDefaults = .standard,
        loadKey: () throws -> String? = { try InworldAPIKeyStore.load() },
        transport: Transport? = nil
    ) async -> String {
        guard repairIsOn(in: defaults) else { return transcript }
        let key: String?
        do {
            key = try loadKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[SpokenRepair] missing key")
            return transcript
        }
        guard let key, !key.isEmpty else {
            print("[SpokenRepair] missing key")
            return transcript
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 1.5)
        request.httpMethod = "POST"
        request.setValue(InworldSTTMessages.authorizationValue(apiKey: key), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try requestBody(transcript: transcript, polish: polishIsOn(in: defaults))
        } catch {
            print("[SpokenRepair] request")
            return transcript
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (transport ?? liveTransport)(request)
        } catch {
            print("[SpokenRepair] transport")
            return transcript
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let text = acceptedText(from: data, status: status, input: transcript) else {
            print("[SpokenRepair] reply")
            return transcript
        }
        return text
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        return URLSession(configuration: configuration)
    }()

    private static func liveTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    private static func strippingOneQuotePair(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'")]
        guard text.count >= 2, let first = text.first, let last = text.last else { return text }
        for (open, close) in pairs where first == open && last == close {
            return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private struct RequestBody: Encodable {
        var model: String
        var temperature: Int
        var stream: Bool
        var maxTokens: Int
        var messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, temperature, stream, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct Message: Encodable {
        var role: String
        var content: String
    }
}

private struct ChatCompletion: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var finishReason: String?
        var message: ReplyMessage

        enum CodingKeys: String, CodingKey {
            case finishReason = "finish_reason"
            case message
        }
    }

    struct ReplyMessage: Decodable {
        var content: String?
    }
}
