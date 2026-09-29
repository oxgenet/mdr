import XCTest

/// Captures the App Store screenshots listed in ios/store/listing.md §7.
///
/// Not part of the normal suite — `ios/store/capture-shots.sh` runs it by
/// name against the two devices whose native resolutions App Store Connect
/// accepts. Kept in the repo because re-shooting by hand is exactly the sort
/// of thing that goes stale: when the UI changes these are re-runnable.
///
/// Plain device screenshots, no frames or captions, per §7.
final class StoreShotTests: XCTestCase {

    private var app = XCUIApplication()

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func open(_ fixture: String) {
        app = XCUIApplication()
        app.launchArguments = ["-openFile", fixture]
        app.launch()
        XCTAssertTrue(app.webViews["documentPage"].waitForExistence(timeout: 30),
                      "\(fixture) did not open")
        XCTAssertTrue(app.webViews["documentPage"].staticTexts.firstMatch.waitForExistence(timeout: 30),
                      "\(fixture) rendered empty")
    }

    /// Tap a nav-bar button, reaching into the "More" overflow if iOS put it
    /// there — the bar collapses differently on iPhone and iPad.
    private func tapBar(_ identifier: String) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: 10) { direct.tap(); return }
        let more = app.buttons["OverflowBarButtonItem"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "\(identifier) is nowhere on the bar")
        more.tap()
        let titles = ["settingsButton": "Settings", "tocButton": "Table of contents"]
        let byTitle = app.buttons[titles[identifier] ?? identifier]
        XCTAssertTrue(byTitle.waitForExistence(timeout: 10), "\(identifier) not in the overflow")
        byTitle.tap()
    }

    /// Jump to a heading through the app's own table of contents, rather than
    /// guessing at scroll offsets that differ per device.
    private func jumpToHeading(containing text: String) {
        tapBar("tocButton")
        XCTAssertTrue(app.navigationBars["Contents"].waitForExistence(timeout: 15),
                      "the table of contents did not open")
        let row = app.tables.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@", text)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no heading containing '\(text)'")
        row.tap()
        XCTAssertTrue(app.navigationBars["Contents"].waitForNonExistence(timeout: 10),
                      "the sheet did not close")
        // Let the smooth scroll settle before the shutter.
        Thread.sleep(forTimeInterval: 2.0)
    }

    func testCaptureStoreShots() throws {
        // 1 — a Mermaid diagram rendered large and legible.
        //
        // Deliberately *not* section 2, "a deliberately large diagram",
        // despite it being the obvious candidate: that fixture exists to be
        // too dense to read at 1x, so at full width it is an unreadable
        // smudge. It is the right subject for the zoom shot below and the
        // wrong one for the shot that has to sell the app.
        // The class diagram: legible at full width, and it happens to describe
        // mdr's own shape. The sequence diagram is more striking but the state
        // diagram directly below it has overlapping labels, which would sit in
        // the frame looking like our bug.
        open("diagrams.md")
        jumpToHeading(containing: "Class diagram")
        shot("01-diagram")

        // 2 — the dense one, pinched open, labels legible at scale. This is
        // the pair the listing wants: big diagrams fit, and zoom rescues them.
        // Zoom the view already framed above rather than jumping elsewhere
        // first: a pinch anchors on the centre of the web view, so zooming
        // straight after a heading jump lands across a section boundary and
        // the frame fills with a fragment of the next heading.
        let page = app.webViews["documentPage"]
        // 2x, not 3x: enough to make the labels readable while the diagram
        // still reads as a diagram. Past that the frame fills with a fragment
        // of a heading and the shot stops being about the diagram at all.
        page.pinch(withScale: 2.0, velocity: 1.0)
        Thread.sleep(forTimeInterval: 2.5)
        shot("02-diagram-zoomed")
        app.terminate()

        // 3 — the table of contents over a long document.
        open("markdown.md")
        tapBar("tocButton")
        XCTAssertTrue(app.navigationBars["Contents"].waitForExistence(timeout: 15),
                      "the table of contents did not open")
        Thread.sleep(forTimeInterval: 1.5)
        shot("03-table-of-contents")
        app.terminate()

        // 4 — a Japanese document: CJK glyph shaping and a CJK-labelled diagram.
        open("ja.md")
        Thread.sleep(forTimeInterval: 2.0)
        shot("04-japanese")
        app.terminate()

        // 5 — Settings, with the image controls visible.
        open("markdown.md")
        tapBar("settingsButton")
        XCTAssertTrue(app.switches["remoteImagesSwitch"].waitForExistence(timeout: 15),
                      "the Images section did not appear")

        // Wait for the Support section to stop moving. It starts on
        // "Loading…" and reloads once the store answers, and the reload
        // animates — a shot fired mid-transition catches the new text ghosted
        // over the old, which looks like a rendering fault rather than a
        // section settling.
        let settled = app.staticTexts["In-app support is not available on this device right now."]
        let tiers = app.cells["tier_tip_coffee_1"]
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline && !settled.exists && !tiers.exists {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(settled.exists || tiers.exists,
                      "the Support section never left its loading state")
        // And let the reload animation finish.
        Thread.sleep(forTimeInterval: 2.0)

        // No hittability probe here: `isHittable` throws outright when an
        // element has no valid activation point, which it briefly does while
        // the sheet is still settling. The section fits without scrolling on
        // both capture devices.
        shot("05-settings-images")
    }
}
