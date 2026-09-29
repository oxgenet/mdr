import XCTest
@testable import MdrApp

/// The Share Extension's payload decisions. The extension itself cannot host
/// XCTest, so the logic lives in `ShareIntake` and is exercised here; what is
/// left in `ShareViewController` is `NSItemProvider` plumbing.
final class ShareIntakeTests: XCTestCase {

    // MARK: naming shared text

    func testTheFirstHeadingBecomesTheFileName() {
        XCTAssertEqual(ShareIntake.stem(forText: "# Release notes\n\nbody"), "Release notes")
    }

    func testASlashInAHeadingDoesNotBecomeAPathSeparator() {
        // `# Chapter 3/4` is legal Markdown and an illegal file name.
        let stem = ShareIntake.stem(forText: "# Chapter 3/4: notes")
        XCTAssertFalse(stem.contains("/"))
        XCTAssertFalse(stem.contains(":"))
    }

    func testEmptyTextStillGetsAName() {
        XCTAssertEqual(ShareIntake.stem(forText: ""), "Shared")
        XCTAssertEqual(ShareIntake.stem(forText: "#  \n\nbody"), "Shared")
    }

    func testALongHeadingIsTruncated() {
        XCTAssertLessThanOrEqual(ShareIntake.stem(forText: "# " + String(repeating: "a", count: 200)).count, 40)
    }

    // MARK: web links

    func testALinkToAMarkdownFileIsWorthFetching() {
        XCTAssertTrue(ShareIntake.isDocumentURL(URL(string: "https://example.com/README.md")!))
        XCTAssertTrue(ShareIntake.isDocumentURL(URL(string: "https://example.com/notes.TXT")!))
    }

    func testAnOrdinaryPageIsNot() {
        XCTAssertFalse(ShareIntake.isDocumentURL(URL(string: "https://example.com/blog/post")!))
        XCTAssertFalse(ShareIntake.isDocumentURL(URL(string: "https://example.com/page.html")!))
    }

    func testALinkNoteCarriesTheTitleAndTheURL() {
        let note = ShareIntake.linkNote(for: URL(string: "https://example.com/post")!, title: "A good post")
        XCTAssertEqual(note, "# A good post\n\n<https://example.com/post>\n")
    }

    func testALinkNoteFallsBackToTheHostWhenThereIsNoTitle() {
        let note = ShareIntake.linkNote(for: URL(string: "https://example.com/post")!, title: "   ")
        XCTAssertTrue(note.hasPrefix("# example.com"), note)
    }

    func testALinkIsNamedForItsTitle() {
        XCTAssertEqual(ShareIntake.stem(for: URL(string: "https://example.com/x")!, title: "A good post"),
                       "A good post")
        XCTAssertEqual(ShareIntake.stem(for: URL(string: "https://example.com/x")!, title: nil),
                       "example.com")
    }

    // MARK: not clobbering the inbox

    func testASecondShareOfTheSameTitleDoesNotOverwriteTheFirst() {
        let taken: Set<String> = ["Notes.md", "Notes 2.md"]
        XCTAssertEqual(ShareIntake.uniqueName("Notes", ext: "md") { taken.contains($0) }, "Notes 3.md")
    }

    func testAFreeNameIsUsedAsIs() {
        XCTAssertEqual(ShareIntake.uniqueName("Notes", ext: "md") { _ in false }, "Notes.md")
    }
}
