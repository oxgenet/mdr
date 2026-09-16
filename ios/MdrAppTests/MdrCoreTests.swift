import XCTest
@testable import MdrApp

/// The iOS half of the mobile contract.
///
/// These assertions deliberately mirror the unit tests in `src/ffi.rs` and the
/// Android suite in `MdrCoreInstrumentedTest.kt`: the same rendering core,
/// reached through the C ABI instead of JNI. The Rust tests prove the core is
/// right; these prove the binding carries it faithfully — `libmdr.a` is linked
/// and current, strings survive the Swift/C boundary in both directions,
/// booleans do not get swapped, and `MdrCore.take` frees every pointer it is
/// handed without leaking or double-freeing.
///
/// Nothing here re-asserts Markdown semantics. If a test would still pass with
/// a Swift reimplementation of the renderer, it belongs in Rust, not here.
///
/// Anything asserted here must hold on Android too. If you change one side,
/// change both — `docs/mobile-test-handoff.md` explains the pairing.
///
/// Note on names: the Android case `aLargeDocumentSurvivesTheJniBoundary` is
/// spelled `...TheFfiBoundary` here, because that is the boundary iOS crosses.
/// It is the same case.
final class MdrCoreTests: XCTestCase {

    /// Eight-byte PNG signature — all the magic-byte validation looks at.
    private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// A fresh directory under the test bundle's temporary area, removed after
    /// the test. `baseDir` behaviour is filesystem-sensitive, so these run
    /// against a real sandboxed iOS path rather than a desktop one.
    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - the binding itself

    func testNativeLibraryLoadsAndReportsItsVersion() {
        // On Android this catches a missing or stale `libmdr.so`. iOS links the
        // core statically, so "missing" is a link error rather than a runtime
        // one — but "stale" is just as possible and just as quiet: the shell
        // would render with whatever core was last built into `libmdr.a`.
        let version = MdrCore.version
        XCTAssertFalse(version.isEmpty, "core reported no version")
        XCTAssertNotNil(
            version.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression),
            "version '\(version)' is not a semver-shaped string"
        )

        let bundleVersion = Bundle(for: type(of: self)).object(
            forInfoDictionaryKey: "MdrHostShortVersion"
        ) as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(
            bundleVersion,
            version,
            "libmdr.a is a different version from the app — rebuild the Rust core, "
                + "or update CFBundleShortVersionString in ios/MdrApp/project.yml"
        )
    }

    func testEmptyInputProducesAPageRatherThanACrash() {
        let html = MdrCore.renderPage(markdown: "", baseDir: "")
        XCTAssertTrue(html.contains("<html"))
        XCTAssertTrue(html.contains("</html>"))
    }

    func testALargeDocumentSurvivesTheFfiBoundary() {
        // String conversion is the size-sensitive part; a ~200k-character
        // document is a realistic worst case for an LLM transcript.
        var markdown = ""
        for i in 0..<4000 {
            markdown += "## Heading \(i)\n\nSome body text for section \(i).\n\n"
        }
        let html = MdrCore.renderPage(markdown: markdown, baseDir: "")
        XCTAssertTrue(html.contains("Heading 3999"))
        XCTAssertTrue(html.contains("</html>"))
    }

    func testRepeatedRenderAndFreeIsStable() {
        // `MdrCore.take` frees every pointer the core returns. A leak or a
        // double-free shows up here first — run this target once under the
        // Address Sanitizer after touching `src/ffi.rs`.
        for i in 0..<200 {
            let html = MdrCore.renderPage(markdown: "# \(i)\n\nbody \(i)", baseDir: "")
            XCTAssertTrue(html.contains("</html>"))
            XCTAssertFalse(MdrCore.updateScript(markdown: "# \(i)", baseDir: "").isEmpty)
            XCTAssertTrue(MdrCore.detectLang(markdown: "これは日本語です。") == "ja")
        }
    }

    // MARK: - view options

    func testViewFlagsReachTheRenderedPage() {
        // editor/toc cross the boundary as C `bool`s; swapping them would open
        // the wrong mode with no other visible symptom.
        XCTAssertTrue(MdrCore.renderPage(markdown: "# t", baseDir: "", editor: false, toc: false)
            .contains(#"<body class="no-toc">"#))
        XCTAssertTrue(MdrCore.renderPage(markdown: "# t", baseDir: "", editor: true, toc: false)
            .contains(#"<body class="no-toc editing">"#))
        XCTAssertTrue(MdrCore.renderPage(markdown: "# t", baseDir: "", editor: false, toc: true)
            .contains(#"<body class="">"#))
        XCTAssertTrue(MdrCore.renderPage(markdown: "# t", baseDir: "", editor: true, toc: true)
            .contains(#"<body class="editing">"#))
    }

    func testDocumentSourceIsEscapedIntoTheEditorPane() {
        let html = MdrCore.renderPage(markdown: "<b>bold</b> & <i>x</i>", baseDir: "", editor: true)
        XCTAssertTrue(
            html.contains("&lt;b&gt;bold&lt;/b&gt; &amp; &lt;i&gt;x&lt;/i&gt;"),
            "source not escaped into <textarea>"
        )
        // comrak runs with `render.unsafe = true` deliberately, so raw HTML in
        // the document still renders in the body.
        XCTAssertTrue(html.contains("<b>bold</b>"), "raw HTML should still render in the body")
    }

    func testHeadingsBecomeTocEntriesTheMenuCanScrape() {
        // DocumentViewController.showToc() reads exactly these elements: the
        // `<li class="toc-hN"><a href="#slug">` it scrapes, and the matching
        // `<h1 id="slug">` the anchor has to land on.
        let html = MdrCore.renderPage(markdown: "# Getting Started\n\n## Install", baseDir: "", toc: true)
        XCTAssertTrue(html.contains(##"<li class="toc-h1"><a href="#getting-started">Getting Started</a></li>"##))
        XCTAssertTrue(html.contains(##"<li class="toc-h2"><a href="#install">Install</a></li>"##))
        XCTAssertTrue(html.contains(#"<h1 id="getting-started">"#))
    }

    // MARK: - language resolution (same order as the Rust core)

    // Nothing here asserts a tag for an empty or Latin-only document:
    // resolution falls back to the OS locale, so such an assertion passes in CI
    // and fails on a Japanese machine. This already bit the project once
    // (CHANGELOG 0.4.0).

    func testLanguageIsDetectedFromContent() {
        XCTAssertEqual("ja", MdrCore.detectLang(markdown: "これは日本語の文書です。"))
        XCTAssertEqual("ko", MdrCore.detectLang(markdown: "이것은 한국어 문서입니다."))
        XCTAssertEqual("zh-Hans", MdrCore.detectLang(markdown: "这是简体中文的文档。"))
    }

    func testFrontMatterBeatsExplicitLangWhichBeatsDetection() {
        let ko = "이것은 한국어 문서입니다."
        XCTAssertEqual("ja", MdrCore.detectLang(markdown: ko, lang: "ja"))
        XCTAssertEqual("zh-Hant", MdrCore.detectLang(markdown: "---\nlang: zh-Hant\n---\n\(ko)", lang: "ja"))
        XCTAssertTrue(MdrCore.renderPage(markdown: ko, baseDir: "", lang: "ja").contains(#"<html lang="ja">"#))
    }

    func testAutoMeansNoExplicitLanguage() {
        XCTAssertEqual("ja", MdrCore.detectLang(markdown: "これは日本語です。", lang: "auto"))
    }

    func testAnUnparseableLanguageTagFallsBackToDetection() {
        XCTAssertEqual("ja", MdrCore.detectLang(markdown: "これは日本語です。", lang: "xx-YY"))
    }

    // MARK: - live update script

    func testUpdateScriptJsonEncodesTheDocument() {
        // The script goes straight to `evaluateJavaScript`, which takes source,
        // not arguments: a raw quote, backslash or newline from the document
        // would be a syntax error, not a failed update.
        //
        // The quote has to come from raw HTML, not from prose: comrak escapes a
        // quote in text to `&quot;`, so `He said "hi"` would prove nothing.
        // `render.unsafe = true` passes an attribute through verbatim, which is
        // the case that actually reaches the JS literal as a raw quote.
        let js = MdrCore.updateScript(markdown: "<span title=\"hi\">x</span>\n\nC:\\path\\to", baseDir: "")
        XCTAssertFalse(js.contains("\n"), "update script must stay on one line: \(js)")
        XCTAssertTrue(js.contains(#"title=\"hi\""#), "quotes not escaped: \(js)")
        XCTAssertTrue(js.contains(#"C:\\path\\to"#), "backslashes not escaped: \(js)")
    }

    func testUpdateScriptTracksTheLanguage() {
        // The page is built once and then updated in place; if the two
        // disagreed, CJK glyphs would change shape mid-edit.
        let md = "---\nlang: zh-Hant\n---\n\nplain text"
        XCTAssertTrue(MdrCore.renderPage(markdown: md, baseDir: "").contains(#"<html lang="zh-Hant">"#))
        XCTAssertTrue(MdrCore.updateScript(markdown: md, baseDir: "").contains(#"setAttribute('lang', "zh-Hant")"#))
    }

    // MARK: - baseDir behaviour on a real iOS filesystem

    func testRelativeImagesAreEmbeddedFromBaseDir() throws {
        // WKWebView loads the page with `baseURL: nil`, so nothing can be
        // fetched from disk afterwards — images have to be inlined at render
        // time.
        let dir = try makeTempDir("img")
        try pngBytes.write(to: dir.appendingPathComponent("pic.png"))
        let html = MdrCore.renderPage(markdown: "![a](pic.png)", baseDir: dir.path)
        XCTAssertTrue(html.contains("data:image/png;base64,"), "image was not inlined")
        XCTAssertFalse(html.contains(#"src="pic.png""#))
    }

    func testImagesOutsideBaseDirAreNotEmbedded() throws {
        // A document can name `../secret.png`; embedding it would lift a file
        // the user never opened into the page.
        let root = try makeTempDir("esc")
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try pngBytes.write(to: root.appendingPathComponent("secret.png"))
        let html = MdrCore.renderPage(markdown: "![a](../secret.png)", baseDir: sub.path)
        XCTAssertFalse(html.contains("data:image/png;base64,"), "image escaped baseDir")
        XCTAssertTrue(html.contains(#"src="../secret.png""#))
    }

    // MARK: - the seeded fixture (replaces build-app.sh's MDR_EXPECT_LANG grep)

    /// `ios/build-app.sh` seeds a document into the app's Documents directory
    /// and may declare the tag it should resolve to. This target is hosted in
    /// the app, so it runs inside the app's sandbox and can read that file —
    /// which is what makes the check possible without grepping NSLog.
    ///
    /// Skipped when the script did not declare an expectation, so the target
    /// still runs standalone from Xcode.
    func testTheSeededFixtureResolvesToItsExpectedLanguage() throws {
        let env = ProcessInfo.processInfo.environment
        let expected = env["MDR_EXPECT_LANG"] ?? ""
        try XCTSkipIf(expected.isEmpty, "MDR_EXPECT_LANG not set — nothing to check")

        let name = env["MDR_FIXTURE"] ?? "ja.md"
        let docs = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            "the app has no Documents directory"
        )
        let url = docs.appendingPathComponent(name)
        let markdown = try XCTUnwrap(
            try? String(contentsOf: url, encoding: .utf8),
            "\(name) was not seeded into the app's Documents directory at \(url.path)"
        )
        XCTAssertEqual(
            expected,
            MdrCore.detectLang(markdown: markdown),
            "\(name) did not resolve to the language the build script expected"
        )
    }

    func testAnEmptyBaseDirStillRenders() {
        // What a document opened from a provider with no filesystem path gives
        // us: no directory at all.
        let html = MdrCore.renderPage(markdown: "# t\n\n![a](pic.png)", baseDir: "")
        XCTAssertTrue(html.contains("</html>"))
        XCTAssertTrue(html.contains(#"src="pic.png""#))
    }
}
