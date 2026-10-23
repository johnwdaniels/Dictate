import XCTest
@testable import Dictate

final class InsightsAndShortcutTests: XCTestCase {
    func testTimeSavedSubtractsDictationFromTypingTime() {
        XCTAssertEqual(InsightsMath.timeSavedSeconds(words: 40, durationSeconds: 0), 60, accuracy: 0.001)
        XCTAssertEqual(InsightsMath.timeSavedSeconds(words: 40, durationSeconds: 60), 0, accuracy: 0.001)
        XCTAssertEqual(InsightsMath.timeSavedSeconds(words: 40, durationSeconds: 90), 0, accuracy: 0.001)
    }

    func testTimeSavedLabelUsesHoursPastOneHour() {
        let saved = InsightsMath.timeSavedLabel(seconds: 1.7 * 3600)
        XCTAssertEqual(saved.value, "1.7")
        XCTAssertEqual(saved.unit, "hours")
    }

    func testWeekSummaryCountsWordsAndSkipsDictationsWithNoApp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_761_264_000) // 2025-10-23 or nearby Thursday
        let samples = [
            InsightSample(date: now, wordCount: 100, durationSeconds: 30, appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            InsightSample(date: now, wordCount: 40, durationSeconds: 10, appName: "", bundleID: ""),
            InsightSample(date: now.addingTimeInterval(-86_400 * 40), wordCount: 999, durationSeconds: 0, appName: "Mail", bundleID: "com.apple.mail"),
        ]

        let summary = InsightsMath.summarize(samples, range: .week, now: now, calendar: calendar)

        XCTAssertEqual(summary.words, 140)
        XCTAssertEqual(summary.apps.map(\.name), ["Slack"])
        XCTAssertEqual(summary.buckets.count, 7)
        XCTAssertEqual(summary.buckets.reduce(0) { $0 + $1.words }, 140)
    }

    func testShortcutRequiresExpansionAndRejectsADuplicatePhrase() {
        XCTAssertEqual(
            SpokenShortcutRules.issue(for: "my email", expansion: "  ", existing: []),
            "Add the text that should be inserted."
        )
        XCTAssertEqual(
            SpokenShortcutRules.issue(for: "My Email", expansion: "a@b.c", existing: ["my email"]),
            "That phrase is already a shortcut."
        )
        XCTAssertTrue(SpokenShortcutRules.canAdd(phrase: "my email", expansion: "a@b.c", existing: []))
    }

    func testShortcutExpandsWithoutTouchingALongerWord() {
        let result = DictionaryReplacements.apply(
            [("email", "post"), ("my email", "a@b.co")],
            to: "Send my email and email"
        )
        XCTAssertEqual(result, "Send a@b.co and post")
    }
}
