import XCTest
@testable import Dictate

final class SpokenRepairTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SpokenRepairTests"

    private let repairPrompt = """
    You edit a speech-to-text transcript. Return only the edited transcript.

    Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

    Fix grammar, agreement, and small words that were dropped. Fix words that are obvious mishearings from context.

    Keep the language of the transcript. Keep names, numbers, and commitments. A question stays a question. Do not answer it. Do not add information. Do not tighten or rephrase beyond what the repair needs.

    No preamble, label, or quotation marks around the result.
    """

    private let polishPrompt = """
    You edit a speech-to-text transcript. Return only the edited transcript.

    Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

    Fix grammar, agreement, small words that were dropped, and words that are obvious mishearings from context. You may tighten and rephrase.

    Keep the meaning, the language, the names, the numbers, and the commitments. A question stays a question. Do not answer it. Do not add information.

    No preamble, label, or quotation marks around the result.
    """

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testRepairAndPolishDefaultToOff() {
        XCTAssertFalse(SpokenRepair.repairIsOn(in: defaults))
        XCTAssertFalse(SpokenRepair.polishIsOn(in: defaults))
    }

    func testPolishStaysOffUntilRepairIsOn() {
        defaults.set(true, forKey: SpokenRepair.polishKey)
        XCTAssertFalse(SpokenRepair.polishIsOn(in: defaults))
        defaults.set(true, forKey: SpokenRepair.repairKey)
        XCTAssertTrue(SpokenRepair.polishIsOn(in: defaults))
    }

    func testMaxTokensFollowsTheCap() {
        XCTAssertEqual(SpokenRepair.maxTokens(for: "ab"), 64)
        XCTAssertEqual(SpokenRepair.maxTokens(for: "Hello"), 65)
        XCTAssertEqual(SpokenRepair.maxTokens(for: String(repeating: "a", count: 20_000)), 4096)
    }

    func testRequestUsesTheRepairPrompt() throws {
        let body = try decode(SpokenRepair.requestBody(transcript: "Hello there", polish: false))
        XCTAssertEqual(body.model, "inworld/models/gemma-4-26b-a4b-it")
        XCTAssertEqual(body.temperature, 0)
        XCTAssertFalse(body.stream)
        XCTAssertEqual(body.maxTokens, 67)
        XCTAssertEqual(body.messages.map(\.role), ["system", "user"])
        XCTAssertEqual(body.messages[0].content, repairPrompt)
        XCTAssertEqual(body.messages[1].content, "Hello there")
    }

    func testRequestUsesThePolishPrompt() throws {
        let body = try decode(SpokenRepair.requestBody(transcript: "Hello there", polish: true))
        XCTAssertEqual(body.messages[0].content, polishPrompt)
        XCTAssertEqual(body.messages[1].content, "Hello there")
    }

    func testAcceptsAReplyAndStripsOneQuotePair() {
        let input = "Hello"
        XCTAssertEqual(accepted("\"Meet Wednesday.\""), "Meet Wednesday.")
        XCTAssertEqual(accepted("\u{201C}Meet Wednesday.\u{201D}"), "Meet Wednesday.")
        XCTAssertEqual(accepted("'Meet Wednesday.'"), "Meet Wednesday.")
        XCTAssertEqual(accepted("Meet Wednesday."), "Meet Wednesday.")
        XCTAssertEqual(
            SpokenRepair.acceptedText(from: completion(content: "Meet Wednesday.", finish: nil, includeFinish: false), status: 200, input: input),
            "Meet Wednesday."
        )
    }

    func testRejectsAnUnusableReply() {
        let input = "Hi"
        XCTAssertNil(SpokenRepair.acceptedText(from: Data(), status: 200, input: input))
        XCTAssertNil(SpokenRepair.acceptedText(from: completion(content: "Hi."), status: 500, input: input))
        XCTAssertNil(SpokenRepair.acceptedText(from: completion(content: "Hi.", finish: "length"), status: 200, input: input))
        XCTAssertNil(SpokenRepair.acceptedText(from: completion(content: "   "), status: 200, input: input))
        XCTAssertNil(SpokenRepair.acceptedText(from: completion(content: "\"\""), status: 200, input: input))
        let long = String(repeating: "a", count: 200)
        XCTAssertNil(SpokenRepair.acceptedText(from: completion(content: long), status: 200, input: input))
    }

    func testRepairOffDoesNotSend() async {
        defaults.set(true, forKey: SpokenRepair.polishKey)
        let result = await SpokenRepair.apply("Hello", defaults: defaults, loadKey: {
            XCTFail("loaded the key")
            return "key"
        }, transport: { _ in
            XCTFail("sent a request")
            return (Data(), URLResponse())
        })
        XCTAssertEqual(result, "Hello")
        XCTAssertFalse(SpokenRepair.polishIsOn(in: defaults))
    }

    func testMissingKeyDoesNotSend() async {
        defaults.set(true, forKey: SpokenRepair.repairKey)
        var sent = false
        let missing = await SpokenRepair.apply("Hello", defaults: defaults, loadKey: { nil }, transport: { _ in
            sent = true
            return (Data(), URLResponse())
        })
        XCTAssertFalse(sent)
        XCTAssertEqual(missing, "Hello")

        let thrown = await SpokenRepair.apply("Hello", defaults: defaults, loadKey: { throw URLError(.cannotOpenFile) }, transport: { _ in
            sent = true
            return (Data(), URLResponse())
        })
        XCTAssertFalse(sent)
        XCTAssertEqual(thrown, "Hello")
    }

    func testApplySendsTheChatCompletion() async throws {
        defaults.set(true, forKey: SpokenRepair.repairKey)
        var request: URLRequest?
        let result = await SpokenRepair.apply(
            "Meet Tuesday, no, Wednesday.",
            defaults: defaults,
            loadKey: { "secret-key" },
            transport: { sent in
                request = sent
                let response = HTTPURLResponse(url: sent.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (self.completion(content: "\"Meet Wednesday.\""), response)
            }
        )
        XCTAssertEqual(result, "Meet Wednesday.")
        let sent = try XCTUnwrap(request)
        XCTAssertEqual(sent.url, SpokenRepair.endpoint)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.timeoutInterval, 1.5)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), InworldSTTMessages.authorizationValue(apiKey: "secret-key"))
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try decode(XCTUnwrap(sent.httpBody))
        XCTAssertEqual(body.messages[0].content, repairPrompt)
        XCTAssertFalse(body.stream)
    }

    func testApplyKeepsTheTranscriptWhenTheReplyIsUnusable() async {
        defaults.set(true, forKey: SpokenRepair.repairKey)
        let input = "Hi"
        let replies: [(Data, Int)] = [
            (Data(), 200),
            (completion(content: "Hi."), 503),
            (completion(content: "Hi.", finish: "length"), 200),
            (completion(content: String(repeating: "a", count: 200)), 200),
        ]
        for reply in replies {
            let result = await SpokenRepair.apply(input, defaults: defaults, loadKey: { "key" }, transport: { _ in
                let response = HTTPURLResponse(url: SpokenRepair.endpoint, statusCode: reply.1, httpVersion: nil, headerFields: nil)!
                return (reply.0, response)
            })
            XCTAssertEqual(result, input)
        }
        let timedOut = await SpokenRepair.apply(input, defaults: defaults, loadKey: { "key" }, transport: { _ in
            throw URLError(.timedOut)
        })
        XCTAssertEqual(timedOut, input)
    }

    func testPolishSendsThePolishPrompt() async throws {
        defaults.set(true, forKey: SpokenRepair.repairKey)
        defaults.set(true, forKey: SpokenRepair.polishKey)
        var body: Data?
        _ = await SpokenRepair.apply("Hello there", defaults: defaults, loadKey: { "key" }, transport: { sent in
            body = sent.httpBody
            let response = HTTPURLResponse(url: SpokenRepair.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (self.completion(content: "Hello."), response)
        })
        let decoded = try decode(XCTUnwrap(body))
        XCTAssertEqual(decoded.messages[0].content, polishPrompt)
    }

    private func accepted(_ content: String) -> String? {
        SpokenRepair.acceptedText(from: completion(content: content), status: 200, input: "Hello")
    }

    private func completion(content: String, finish: String? = "stop", includeFinish: Bool = true) -> Data {
        var choice: [String: Any] = ["message": ["role": "assistant", "content": content]]
        if includeFinish, let finish {
            choice["finish_reason"] = finish
        }
        return try! JSONSerialization.data(withJSONObject: ["choices": [choice]])
    }

    private struct Body: Decodable {
        var model: String
        var temperature: Int
        var stream: Bool
        var maxTokens: Int
        var messages: [Message]

        struct Message: Decodable {
            var role: String
            var content: String
        }

        enum CodingKeys: String, CodingKey {
            case model, temperature, stream, messages
            case maxTokens = "max_tokens"
        }
    }

    private func decode(_ data: Data) throws -> Body {
        try JSONDecoder().decode(Body.self, from: data)
    }
}
