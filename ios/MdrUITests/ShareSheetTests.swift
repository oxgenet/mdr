import XCTest

/// The Share Extension, driven the only way it can be: from another app's
/// share sheet.
///
/// This is the test that could not exist while `docs/ios-release-checklist.md`
/// §8 said "the Share Extension has never run", for two reasons, both now
/// fixed. App Groups need a signed build, so it only means anything on a
/// device. And the activation rule accepted text and files but not web URLs,
/// so mdr never appeared in Safari's share sheet at all — there was nothing
/// to tap.
///
/// Safari's chrome is not ours and it moves between releases: on iOS 26 the
/// toolbar is a capsule and Share sits inside the More menu rather than on the
/// bar. Each step therefore fails with the element it wanted, so the next
/// reshuffle produces a diagnosis instead of a timeout.
final class ShareSheetTests: XCTestCase {

    private let page = "https://example.com"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMdrAppearsInSafarisShareSheetForAWebPage() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "This verifies nothing on a simulator and fails there for reasons that are not "
            + "about mdr. App Groups do not exist on an unsigned simulator build, so even if "
            + "the extension were offered it could not deliver the file — ShareInboxTests "
            + "skips for the same reason. It also drives Safari against a live URL, so on a "
            + "loaded CI machine it fails on the page load rather than on anything we wrote. "
            + "This is a device test: ios/build-device.sh and a connected phone are where it "
            + "means something."
        )
        #endif

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30), "Safari did not come to the foreground")

        try load(page, in: safari)
        try openShareSheet(in: safari)

        let mdr = try shareTarget(in: safari)
        XCTAssertTrue(mdr.waitForExistence(timeout: 15), """
            mdr is not offered as a share target for a web page. Either the Share Extension's \
            NSExtensionActivationRule is missing NSExtensionActivationSupportsWebURLWithMaxCount, \
            or the extension is not installed on this device.
            """)

        mdr.tap()

        // The extension shows "Saving to mdr…" and completes the request,
        // which puts Safari back in front. A crash or a cancelled request
        // would leave the sheet up instead.
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30),
                      "the share sheet never dismissed — the extension did not complete its request")
        XCTAssertFalse(safari.buttons["ShareButton"].exists,
                       "the share sheet is still open, so the extension did not finish")
    }

    // MARK: - Safari plumbing

    private func load(_ url: String, in safari: XCUIApplication) throws {
        let capsule = safari.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH 'CapsuleNavigationBar'")).firstMatch
        guard capsule.waitForExistence(timeout: 20) else {
            throw XCTSkip("Safari's capsule toolbar was not found; its chrome has changed again")
        }
        capsule.tap()

        let field = safari.textFields["URL"]
        guard field.waitForExistence(timeout: 10) else {
            throw XCTSkip("Safari's address field ('URL') was not found; its chrome has changed again")
        }
        safari.typeText(url + "\n")

        // Wait for the load rather than sleeping.
        XCTAssertTrue(safari.buttons["MoreMenuButton"].waitForExistence(timeout: 30),
                      "Safari never finished loading \(url)")
    }

    /// On iOS 26 Share is not on the toolbar; it is a row in the More menu.
    private func openShareSheet(in safari: XCUIApplication) throws {
        let more = safari.buttons["MoreMenuButton"]
        guard more.waitForExistence(timeout: 20) else {
            throw XCTSkip("Safari's More button was not found; its chrome has changed again")
        }
        more.tap()

        let share = safari.buttons["ShareButton"]
        guard share.waitForExistence(timeout: 10) else {
            throw XCTSkip("Safari's Share row was not found in the More menu")
        }
        share.tap()
    }

    /// mdr's row in the share sheet. The extension's display name is "mdr".
    ///
    /// iOS does not put a newly installed share extension in the front row: the
    /// sheet offers a curated set (AirDrop, Messages, Mail, Notes, Reminders)
    /// and hides the rest behind "View More", where each one has a switch. So
    /// this looks in the front row first and then behind View More — and if it
    /// is there but switched off, only the person holding the phone can turn it
    /// on. That one-time enable is a real part of the product's first-run
    /// experience, not a test artefact.
    private func shareTarget(in safari: XCUIApplication) throws -> XCUIElement {
        let match = NSPredicate(format: "label ==[c] %@", "mdr")
        let anywhere = safari.descendants(matching: .any).matching(match)
        if anywhere.firstMatch.waitForExistence(timeout: 8) { return anywhere.firstMatch }

        let viewMore = safari.cells.matching(NSPredicate(format: "label == 'View More'")).firstMatch
        guard viewMore.waitForExistence(timeout: 5) else { return anywhere.firstMatch }
        viewMore.tap()
        _ = anywhere.firstMatch.waitForExistence(timeout: 8)
        return anywhere.firstMatch
    }
}
