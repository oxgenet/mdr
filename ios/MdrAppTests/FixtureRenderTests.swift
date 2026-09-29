import XCTest
@testable import MdrApp

/// Renders the shared end-to-end fixtures through the C ABI on a simulator.
///
/// These are the same documents `tests/fixtures.rs` renders on the desktop and
/// `FixtureRenderTest.kt` renders through JNI on a device. They are not copied
/// into this target — `ios/build-app.sh` seeds `tests/samples/e2e` into the
/// app's Documents directory and this reads them from there, so the three
/// suites cannot drift apart.
///
/// What is proved here is the iOS path specifically: real files on a real
/// sandboxed filesystem, images resolved from a real directory, and strings
/// crossing the C ABI at the size a genuine document reaches.
///
/// Several fixtures are deliberately malformed. Surviving them is the point.
final class FixtureRenderTests: XCTestCase {

    /// The app's Documents directory, where build-app.sh seeded the fixtures.
    private var docs: URL {
        get throws {
            try XCTUnwrap(
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                "the app has no Documents directory"
            )
        }
    }

    private func markdown(_ name: String) throws -> String {
        let url = try docs.appendingPathComponent(name)
        return try XCTUnwrap(
            try? String(contentsOf: url, encoding: .utf8),
            "\(name) was not seeded into Documents — run ios/build-app.sh, which copies "
                + "tests/samples/e2e there. Present: \(seededNames().joined(separator: ", "))"
        )
    }

    /// Render a fixture the way the shell does: its own directory as baseDir.
    private func render(_ name: String) throws -> String {
        let dir = try docs.path
        return MdrCore.renderPage(markdown: try markdown(name), baseDir: dir, toc: true)
    }

    private func seededNames() -> [String] {
        guard let d = try? docs,
              let names = try? FileManager.default.contentsOfDirectory(atPath: d.path)
        else { return [] }
        return names.sorted()
    }

    /// The rendered document without the surrounding chrome.
    ///
    /// The page also embeds the untouched source in the editor `<textarea>`, so
    /// searching the whole page cannot tell "this was rendered" from "this was
    /// offered for editing" — front matter legitimately appears in the second.
    private func bodyOf(_ html: String) throws -> String {
        let start = try XCTUnwrap(html.range(of: #"<div class="content">"#), "no content block")
        let rest = html[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: #"<div id="kebab">"#), "no chrome after content")
        return String(rest[..<end.lowerBound])
    }

    // MARK: - the whole set

    func testEveryFixtureRendersCompletely() throws {
        let names = seededNames().filter { $0.hasSuffix(".md") }
        XCTAssertGreaterThanOrEqual(
            names.count, 4,
            "expected the e2e fixture set in Documents, found: \(names.joined(separator: ", "))"
        )
        for name in names {
            let html = try render(name)
            XCTAssertTrue(html.contains("<html"), "\(name): no page produced")
            XCTAssertTrue(html.contains("</html>"), "\(name): page was truncated")
            XCTAssertGreaterThan(html.count, 5_000, "\(name): suspiciously small (\(html.count))")
        }
    }

    // MARK: - language

    func testFrontMatterIsStrippedAndItsLanguageWins() throws {
        // Only CJK tags mean anything to the core's language resolution, so the
        // fixture declares zh-Hant — which detection would never pick for a
        // mostly-English document that happens to contain Japanese and Korean.
        let html = try render("markdown.md")
        XCTAssertTrue(html.contains(#"<html lang="zh-Hant">"#), "front matter lang ignored")
        XCTAssertFalse(
            try bodyOf(html).contains("author: mdr test suite"),
            "front matter was rendered into the document body"
        )
        XCTAssertTrue(
            html.contains("author: mdr test suite"),
            "the editor lost the front matter"
        )
    }

    /// Detection, as opposed to the override above. Front matter winning is a
    /// different claim from detection working at all, and the e2e fixture only
    /// demonstrates the first — so ja.md is seeded alongside it.
    func testContentDetectionStillReachesTheLangAttribute() throws {
        let html = try render("ja.md")
        XCTAssertTrue(
            html.contains(#"<html lang="ja">"#),
            "Japanese content did not resolve to ja through the C ABI"
        )
    }

    // MARK: - images

    func testLocalImagesEmbedAndBadOnesDoNot() throws {
        let html = try render("images.md")
        XCTAssertTrue(html.contains("data:image/png;base64,"), "a valid local PNG was not embedded")
        XCTAssertTrue(html.contains("Invalid image"), "a mislabelled image was embedded")
        XCTAssertTrue(html.contains(#"src="assets/nope.png""#), "a missing image was altered")
    }

    func testTheRemoteImagePolicyHoldsOnDevice() throws {
        // Policy is process-global, and other tests flip it. Put it back where
        // the app starts so this asserts the shipped default.
        MdrCore.remoteImages = true
        MdrCore.allowLocalHttp = true
        let html = try render("images.md")
        XCTAssertTrue(html.contains(#"src="https://example.com/chart.png""#), "https should be allowed")
        XCTAssertTrue(html.contains(#"src="http://192.168.1.10/photo.png""#), "private http should be allowed")
        XCTAssertFalse(html.contains(#"src="http://example.com/insecure.png""#), "public http should be blocked")
        XCTAssertTrue(html.contains("img-blocked"), "blocked images should become placeholders")
    }

    // MARK: - diagrams and links

    func testEveryMermaidBlockIsProcessed() throws {
        let html = try render("diagrams.md")
        XCTAssertFalse(
            html.contains(#"class="language-mermaid""#),
            "a mermaid block was left unprocessed"
        )
        XCTAssertTrue(
            html.contains("mermaid-diagram") || html.contains(#"class="mermaid""#),
            "no diagram was produced"
        )
        XCTAssertTrue(html.contains("Gantt"), "the document stopped at a broken diagram")
    }

    func testLinksSurviveRenderingOnDevice() throws {
        // The javascript:/data:/vbscript: guard lives in the shared page
        // template and tests/fixtures.rs pins it against a freshly built core.
        // Asserting it here too would only add a second failure whenever the
        // linked libmdr.a lags behind src/core/page.rs, which says nothing
        // about iOS. What matters on this side is that the document's links
        // come through the C ABI intact.
        let html = try render("links.md")
        XCTAssertTrue(html.contains("https://example.com/reference"), "reference-style link lost")
        XCTAssertTrue(html.contains("mailto:someone@example.com"), "mailto lost")
        XCTAssertTrue(html.contains("markdown.md"), "relative document link lost")
    }

    func testALargeDocumentSurvivesTheFfiBoundaryIntact() throws {
        // markdown.md is the widest spread of constructs; check the far end of
        // it arrives, not just the opening.
        let html = try render("markdown.md")
        XCTAssertTrue(html.contains("The end."), "the tail of the document is missing")
        XCTAssertTrue(html.contains("<table>"), "table did not render")
        XCTAssertTrue(html.contains("footnotes"), "footnotes did not render")
    }
}
