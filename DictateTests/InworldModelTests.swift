import XCTest
@testable import Dictate

final class InworldModelTests: XCTestCase {
    func testPreviewAndStandardModelsAreDistinctInTheStartMessage() throws {
        let preview = try InworldSTTMessages.startMessage(
            language: nil,
            prompts: [],
            modelId: InworldModelMemory.preview
        )
        let standard = try InworldSTTMessages.startMessage(
            language: nil,
            prompts: [],
            modelId: InworldModelMemory.standard
        )

        XCTAssertTrue(preview.contains(InworldModelMemory.preview))
        XCTAssertTrue(standard.contains("\"modelId\":\"\(InworldModelMemory.standard)\""))
        XCTAssertFalse(standard.contains(InworldModelMemory.preview))
    }

    func testAModelRefusalIsNotTreatedAsABadKey() {
        XCTAssertTrue(DictationFailure.looksLikeUnavailableModel("Permission denied\nPERMISSION_DENIED 7"))
        XCTAssertTrue(DictationFailure.looksLikeUnavailableModel("Model inworld/inworld-stt-1-preview not found"))
        XCTAssertFalse(DictationFailure.looksLikeRejectedKey("Permission denied\nPERMISSION_DENIED 7"))
        XCTAssertFalse(DictationFailure.looksLikeUnavailableModel("401 Unauthorized"))
        XCTAssertTrue(DictationFailure.looksLikeRejectedKey("invalid api key"))
    }

    func testARememberedModelIsReusedWithoutAnotherDefaultsWrite() {
        let key = "model-memory-\(UUID().uuidString)"
        defer { InworldModelMemory.forget(key) }

        XCTAssertNil(InworldModelMemory.remembered(for: key))
        InworldModelMemory.remember(InworldModelMemory.preview, for: key)
        InworldModelMemory.remember(InworldModelMemory.preview, for: key)

        XCTAssertEqual(InworldModelMemory.remembered(for: key), InworldModelMemory.preview)
        XCTAssertEqual(InworldModelMemory.order(for: key).first, InworldModelMemory.preview)
    }

    func testTheShownServerLineOmitsTheStatusDetail() {
        let shown = DictationFailure.serverMessage("Permission denied\nPERMISSION_DENIED 7")

        XCTAssertEqual(shown, "Permission denied")
    }
}
