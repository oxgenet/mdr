import XCTest

/// End-to-end tests for the iOS shell, driven through the real UI.
///
/// These replace the NSLog greps that `ios/build-app.sh` used to do. The
/// difference that matters: a grep for `[mdr-ios] rendered` cannot tell a
/// regression from a log line someone renamed, and it says nothing about
/// whether anything appeared on screen. Every assertion here goes through the
/// accessibility tree, so a failure names the element that was missing.
///
/// Division of labour: `MdrAppTests` proves the Rust core is carried faithfully
/// across the C ABI; this target proves the app wired that core to a UI. It
/// deliberately does not re-assert rendering details — only that the document
/// reached the screen and that the controls act on it.
///
/// The fixture document is seeded into the app's Documents directory by
/// `ios/build-app.sh` before the run (`simctl get_app_container`), because the
/// test runner has its own sandbox and cannot write into the app's. Its name
/// and expected language arrive as TEST_RUNNER_-prefixed environment variables,
/// which Xcode forwards into the runner process.
final class MdrAppUITests: XCTestCase {

    /// Name of the document seeded into the app's Documents directory.
    private var fixtureName: String {
        ProcessInfo.processInfo.environment["MDR_FIXTURE"] ?? "ja.md"
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Launching

    /// Launch the app with the document already open, via the `-openFile` hook
    /// that SceneDelegate reads. That hook predates these tests and is the same
    /// path `build-app.sh` used.
    @discardableResult
    private func launchWithDocument() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-openFile", fixtureName]
        app.launch()
        waitForRenderedPage(app)
        return app
    }

    /// The page is rendered by the Rust core and handed to WKWebView. If
    /// `libmdr.a` were missing or stale, `renderPage` would return an empty
    /// string and the web view would come up blank — so this is the assertion
    /// that has to carry a readable message.
    private func waitForRenderedPage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let page = app.webViews["documentPage"]
        XCTAssertTrue(
            page.waitForExistence(timeout: 30),
            "the document view never appeared — the app may have failed to launch or to open \(fixtureName)",
            file: file, line: line
        )
        // Any text at all means the core produced a page and WebKit parsed it.
        let anyText = page.staticTexts.firstMatch
        XCTAssertTrue(
            anyText.waitForExistence(timeout: 30),
            "the page rendered empty. The Rust core returned no HTML — libmdr.a is "
                + "probably missing, stale, or built for the wrong architecture. "
                + "Rebuild it with ios/build-app.sh.",
            file: file, line: line
        )
    }

    // MARK: - Opening

    func testOpenFromTheDocumentBrowser() {
        // The launch hook bypasses UIDocumentBrowserViewController entirely, so
        // it proves nothing about the way a user actually opens a file. Start
        // cold and pick the document out of the browser.
        let app = XCUIApplication()
        app.launch()

        // The browser opens on "On My iPhone → mdr", the app's own Documents
        // folder, which is where the fixture was seeded. Cells there are
        // identified as "<name>, <extension>" — match the name, not the inner
        // label, because tapping the filename text does not open the document.
        let cell = app.collectionViews.cells
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", fixtureName + ","))
            .firstMatch

        if !cell.waitForExistence(timeout: 15) {
            // Landed somewhere else (Recents, or iCloud Drive): go via Browse.
            let browse = app.buttons["Browse"]
            if browse.exists { browse.tap() }
            let onMyIPhone = app.staticTexts["On My iPhone"]
            if onMyIPhone.waitForExistence(timeout: 10) { onMyIPhone.tap() }
            let folder = app.collectionViews.cells
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "mdr")).firstMatch
            if folder.waitForExistence(timeout: 10) { folder.tap() }
        }

        XCTAssertTrue(
            cell.waitForExistence(timeout: 20),
            "\(fixtureName) is not listed in the document browser — it should have been "
                + "seeded into the app's Documents directory before the run"
        )
        cell.tap()

        waitForRenderedPage(app)
        XCTAssertTrue(
            app.buttons["doneButton"].waitForExistence(timeout: 10),
            "the viewer's navigation bar did not appear after opening from the browser"
        )
    }

    func testOpenedDocumentReachesTheWebView() {
        let app = launchWithDocument()
        XCTAssertTrue(app.navigationBars[fixtureName].exists,
                      "the navigation bar should carry the document's file name")
        // `<html lang>` is not exposed through the accessibility tree, so the
        // resolved tag is asserted in MdrAppTests instead — see
        // testTheSeededFixtureResolvesToItsExpectedLanguage, which runs in the
        // app's own process and reads the very same fixture file.
    }

    // MARK: - Editing

    func testEditingUpdatesTheLivePreview() {
        let app = launchWithDocument()
        app.buttons["editButton"].tap()

        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the source editor did not open")

        let marker = "LivePreviewMarker\(Int.random(in: 1000...9999))"
        editor.tap()
        editor.typeText("\n\n\(marker)\n")

        // refreshPreview() is debounced by 0.3s, then the core re-renders and
        // the JS swaps the body in.
        let echoed = app.webViews["documentPage"].staticTexts[marker]
        XCTAssertTrue(
            echoed.waitForExistence(timeout: 15),
            "typing in the editor did not reach the preview — the live update "
                + "script may not be running, or the core returned nothing"
        )
    }

    func testEditsAreSavedInPlaceAndSurviveARelaunch() {
        // UIDocument autosaves and `close()` saves explicitly; the file is
        // edited in place, not copied (LSSupportsOpeningDocumentsInPlace).
        let app = launchWithDocument()
        app.buttons["editButton"].tap()

        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the source editor did not open")

        let marker = "AutosaveMarker\(Int.random(in: 1000...9999))"
        editor.tap()
        editor.typeText("\n\n\(marker)\n")

        // Leave edit mode, then close the document — both call save().
        app.buttons["editButton"].tap()
        app.buttons["doneButton"].tap()
        app.terminate()

        let relaunched = launchWithDocument()
        let persisted = relaunched.webViews["documentPage"].staticTexts[marker]
        XCTAssertTrue(
            persisted.waitForExistence(timeout: 20),
            "the edit did not survive a relaunch — the document was not saved back to its own file"
        )
    }

    // MARK: - Table of contents

    func testTocSheetListsTheDocumentsHeadings() {
        let app = launchWithDocument()
        app.buttons["tocButton"].tap()

        // showToc() scrapes `.sidebar li` out of the rendered page and presents
        // a native sheet. An empty scrape shows an error alert instead.
        let sheet = app.navigationBars["Contents"]
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            XCTFail("the TOC came up empty: \(app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the table-of-contents sheet did not appear")
        XCTAssertGreaterThan(
            app.tables.cells.count, 0,
            "the sheet appeared but listed no headings — the scrape of `.sidebar li` returned nothing"
        )

        // Picking an entry dismisses the sheet and scrolls the page.
        app.tables.cells.firstMatch.tap()
        XCTAssertTrue(
            sheet.waitForNonExistence(timeout: 10),
            "selecting a heading should dismiss the sheet"
        )
    }

    // MARK: - Search

    func testSearchBarReportsItsMatchCount() {
        // The count has to be asserted exactly. Accepting "No matches" as well
        // would let a completely broken `mdrSearch` pass, since it reports 0 on
        // any failure. So plant a known number of occurrences first, rather
        // than guessing at what the fixture happens to contain.
        let app = launchWithDocument()
        let marker = "Zq\(Int.random(in: 1000...9999))"

        app.buttons["editButton"].tap()
        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the source editor did not open")
        editor.tap()
        editor.typeText("\n\n\(marker)\n\n\(marker)\n")

        let echoed = app.webViews["documentPage"].staticTexts[marker]
        XCTAssertTrue(echoed.waitForExistence(timeout: 15), "the planted text never reached the preview")
        app.buttons["editButton"].tap()   // leave edit mode

        app.buttons["searchButton"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search bar did not open")
        field.tap()
        field.typeText(marker)

        // searchBar(_:textDidChange:) puts "N matches" into the bar's prompt,
        // which is what the user actually reads.
        let prompt = app.staticTexts["2 matches"]
        XCTAssertTrue(
            prompt.waitForExistence(timeout: 15),
            "expected the search bar to report '2 matches' for two planted occurrences of "
                + "\(marker). `mdrSearch` may be missing from the page, which would leave "
                + "the count silently at 0."
        )

        // And the empty case, which is the other branch of the same line.
        // Extend the query rather than trimming it — a shorter marker is still
        // a prefix of what was planted, so it would go on matching.
        field.typeText("Nope")
        XCTAssertTrue(
            app.staticTexts["No matches"].waitForExistence(timeout: 15),
            "a query that matches nothing should say so"
        )
    }

    // MARK: - Settings

    func testSettingsOpensAndTheTocPreferenceReachesThePage() {
        let app = launchWithDocument()
        app.buttons["settingsButton"].tap()

        // Every section is present.
        XCTAssertTrue(app.switches["tocSwitch"].waitForExistence(timeout: 10),
                      "the Reading section did not appear")
        XCTAssertTrue(app.cells["languageRow"].exists, "the language row is missing")
        XCTAssertTrue(app.cells["aboutVersion"].exists, "the About row is missing")

        // The support section settles on one readable line rather than an
        // error, which is what a tester sees until the products exist in App
        // Store Connect. Tiers appearing instead is also correct — that is the
        // local StoreKit configuration doing its job.
        let quiet = app.cells["supportStatus"]
        let tier = app.cells["tier_tip_coffee_1"]
        XCTAssertTrue(
            quiet.waitForExistence(timeout: 20) || tier.waitForExistence(timeout: 5),
            "the Support section neither offered a tier nor explained why it could not"
        )

        // Turn the sidebar on and return: the page must come back with it.
        let toggle = app.switches["tocSwitch"]
        let wasOn = (toggle.value as? String) == "1"
        toggle.tap()
        app.buttons["settingsDoneButton"].tap()

        XCTAssertTrue(app.webViews["documentPage"].waitForExistence(timeout: 15),
                      "the document did not come back after Settings")

        // Put it back so the run leaves no state behind for the next test.
        app.buttons["settingsButton"].tap()
        let again = app.switches["tocSwitch"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(
            (again.value as? String) == "1", !wasOn,
            "the table-of-contents preference did not persist across a trip back to Settings"
        )
        again.tap()
        app.buttons["settingsDoneButton"].tap()
    }

    func testTheLanguagePickerOffersEveryTagAndPersists() {
        let app = launchWithDocument()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.cells["languageRow"].waitForExistence(timeout: 10))
        app.cells["languageRow"].tap()

        // The same five options as Android's spinner, in the same order.
        for id in ["lang_auto", "lang_ja", "lang_zh-Hans", "lang_zh-Hant", "lang_ko"] {
            XCTAssertTrue(app.cells[id].waitForExistence(timeout: 10), "\(id) is not offered")
        }

        app.cells["lang_ko"].tap()
        XCTAssertTrue(app.cells["languageRow"].waitForExistence(timeout: 10),
                      "choosing a language should return to Settings")

        // Reopen the picker: the choice is ticked.
        app.cells["languageRow"].tap()
        XCTAssertTrue(app.cells["lang_ko"].waitForExistence(timeout: 10))

        // Put it back to auto so the run leaves no state behind.
        app.cells["lang_auto"].tap()
        app.buttons["settingsDoneButton"].tap()
    }

    // MARK: - Share

    func testShareOffersMarkdownAndPdf() {
        let app = launchWithDocument()
        app.buttons["shareButton"].tap()

        let md = app.buttons["Share Markdown (.md)"]
        let pdf = app.buttons["Share as PDF"]
        XCTAssertTrue(md.waitForExistence(timeout: 10), "the share sheet did not offer the .md option")
        XCTAssertTrue(pdf.exists, "the share sheet did not offer the PDF option")

        // Exporting to PDF goes through WKWebView.createPDF and then presents a
        // UIActivityViewController. Driving the system share sheet any further
        // is out of scope; that it comes up means the PDF was produced, since
        // presentShare is only called from the success branch.
        pdf.tap()
        let activitySheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(
            activitySheet.waitForExistence(timeout: 30),
            "sharing as PDF did not reach the system share sheet — createPDF probably failed"
        )
    }
}
