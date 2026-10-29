import XCTest
@testable import Dictate

final class ReleaseNotesTests: XCTestCase {
    func testSplitsParagraphsAndBullets() {
        let note = ReleaseNote(version: "1.5.5", markdown: """
        You know that thing where you dictate
        a beautiful paragraph?

        So now there's **Paste Last Dictation.**

        The short version:

        - New: **Paste Last Dictation**.
        - No default key.
        """)

        XCTAssertEqual(note.blocks, [
            .paragraph("You know that thing where you dictate a beautiful paragraph?"),
            .paragraph("So now there's **Paste Last Dictation.**"),
            .paragraph("The short version:"),
            .bullets(["New: **Paste Last Dictation**.", "No default key."]),
        ])
    }

    func testBulletsRightUnderALineStartANewList() {
        let note = ReleaseNote(version: "1.0", markdown: "The short version:\n- One\n- Two\nAfter.")

        XCTAssertEqual(note.blocks, [
            .paragraph("The short version:"),
            .bullets(["One", "Two"]),
            .paragraph("After."),
        ])
    }

    func testBundledNotesAreNewestFirst() {
        let versions = ReleaseNote.bundled(in: Bundle(for: AppDelegate.self)).map(\.version)

        XCTAssertFalse(versions.isEmpty)
        XCTAssertEqual(versions, versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending })
    }
}
