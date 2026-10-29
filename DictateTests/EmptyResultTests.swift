import XCTest
@testable import Dictate

final class EmptyResultTests: XCTestCase {
    func testNoReplyFromInworldReadsAsUnreachable() {
        let message = DictationFailure.emptyResult(heardFromServer: false, timedOut: true, sentAudio: true, peak: 9_000)

        XCTAssertEqual(message, DictationFailure.unreachable)
    }

    func testAudioThatNeverRoseAboveSilenceBlamesTheMicrophone() {
        let message = DictationFailure.emptyResult(heardFromServer: true, timedOut: false, sentAudio: true, peak: 0)

        XCTAssertEqual(message, DictationFailure.silentAudio)
    }

    func testLiveAudioWithNoWordsIsStillNoSpeech() {
        let message = DictationFailure.emptyResult(heardFromServer: true, timedOut: false, sentAudio: true, peak: 4_000)

        XCTAssertEqual(message, DictationFailure.emptyTranscript)
    }

    func testATimeoutAfterTheServerAnsweredIsStillATimeout() {
        let message = DictationFailure.emptyResult(heardFromServer: true, timedOut: true, sentAudio: true, peak: 4_000)

        XCTAssertEqual(message, DictationFailure.timedOut)
    }

    func testThePeakIsTheLoudestSampleEitherSign() {
        let samples: [Int16] = [12, -3_000, 2_500, Int16.min]
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        XCTAssertEqual(PCMConversion.peak(of: data), 32_768)
        XCTAssertEqual(PCMConversion.peak(of: Data(count: 3_200)), 0)
    }

    func testUnreachableIsShownForTheConnectionTest() {
        XCTAssertEqual(InworldSTTError.unreachable.localizedDescription, DictationFailure.unreachable)
    }

    func testInworldsRefusalsReadAsARejectedKey() {
        XCTAssertTrue(DictationFailure.looksLikeRejectedKey("Invalid authorization credentials"))
        XCTAssertTrue(DictationFailure.looksLikeRejectedKey("authentication is required\n16"))
    }
}
