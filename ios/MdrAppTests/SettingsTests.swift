import XCTest
import UIKit
@testable import MdrApp

/// The config screen, including how the tip jar behaves when the store has
/// nothing to sell.
///
/// Mirrors `SettingsActivityTest` on Android. That last part matters more than
/// it sounds: until the in-app purchases are live in App Store Connect — and on
/// any device with purchases restricted — the support section is permanently in
/// its unavailable state. It has to read as a calm sentence, not a crash or an
/// error dialog, because that is what every tester will see first.
@MainActor
final class SettingsTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var prefs: Prefs!

    override func setUp() {
        super.setUp()
        // A private suite per test, so these never disturb the simulator's
        // real preferences and never leak into each other.
        suiteName = "mdr.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        prefs = Prefs(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Load the screen the way a presentation would, without a real store.
    private func makeScreen() -> SettingsViewController {
        let vc = SettingsViewController(prefs: prefs)
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.tableView.layoutIfNeeded()
        return vc
    }

    private func cell(_ vc: SettingsViewController, _ section: Int, _ row: Int) -> UITableViewCell {
        vc.tableView(vc.tableView, cellForRowAt: IndexPath(row: row, section: section))
    }

    // MARK: - structure

    func testTheScreenOpensWithEverySection() {
        let vc = makeScreen()
        XCTAssertEqual(3, vc.numberOfSections(in: vc.tableView), "expected Reading, Support and About")

        XCTAssertEqual("Reading", vc.tableView(vc.tableView, titleForHeaderInSection: 0))
        XCTAssertNotNil(vc.tableView(vc.tableView, titleForHeaderInSection: 1))
        XCTAssertEqual("About", vc.tableView(vc.tableView, titleForHeaderInSection: 2))

        // Reading carries both controls.
        XCTAssertEqual(2, vc.tableView(vc.tableView, numberOfRowsInSection: 0))
        XCTAssertTrue(cell(vc, 0, 0).accessoryView is UISwitch, "toc switch missing")
        XCTAssertEqual("languageRow", cell(vc, 0, 1).accessibilityIdentifier, "language picker missing")
        XCTAssertEqual("aboutVersion", cell(vc, 2, 0).accessibilityIdentifier, "about line missing")
    }

    func testTheAboutLineShowsTheLoadedCoreVersion() {
        let vc = makeScreen()
        let content = cell(vc, 2, 0).contentConfiguration as? UIListContentConfiguration
        let text = content?.text ?? ""
        XCTAssertFalse(MdrCore.version.isEmpty, "the core reported no version")
        XCTAssertTrue(
            text.contains(MdrCore.version),
            "about line '\(text)' does not contain the core version '\(MdrCore.version)'"
        )
    }

    // MARK: - reading preferences

    func testTogglingTheTocSwitchPersists() throws {
        let vc = makeScreen()
        XCTAssertFalse(prefs.showToc, "should default to off")

        let toggle = try XCTUnwrap(cell(vc, 0, 0).accessoryView as? UISwitch)
        XCTAssertEqual("tocSwitch", toggle.accessibilityIdentifier)
        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(prefs.showToc, "switch did not reach preferences")

        // A second screen reads it back, which is what the viewer does when it
        // returns from Settings.
        let reopened = makeScreen()
        let reread = try XCTUnwrap(cell(reopened, 0, 0).accessoryView as? UISwitch)
        XCTAssertTrue(reread.isOn)
    }

    func testChoosingALanguagePersistsItsTag() {
        let vc = makeScreen()
        var chosen: String?
        let picker = LanguagePickerViewController(selected: prefs.lang) { tag in
            chosen = tag
            self.prefs.lang = tag
        }
        picker.loadViewIfNeeded()
        let row = Prefs.langIndex("zh-Hant")
        picker.tableView(picker.tableView, didSelectRowAt: IndexPath(row: row, section: 0))

        XCTAssertEqual("zh-Hant", chosen)
        XCTAssertEqual("zh-Hant", prefs.lang)

        // And the row on the settings screen now shows it.
        let reopened = makeScreen()
        let content = cell(reopened, 0, 1).contentConfiguration as? UIListContentConfiguration
        XCTAssertEqual("Chinese (Traditional)", content?.secondaryText)
        _ = vc
    }

    func testTheLanguagePickerOffersEveryTagWithAutoFirst() {
        let picker = LanguagePickerViewController(selected: "") { _ in }
        picker.loadViewIfNeeded()
        XCTAssertEqual(Prefs.langTags.count, picker.tableView(picker.tableView, numberOfRowsInSection: 0))
        let first = picker.tableView(picker.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(.checkmark, first.accessoryType, "auto should be ticked when no tag is set")
    }

    // MARK: - the tip jar

    func testTheSupportSectionDegradesQuietlyWithoutConfiguredProducts() {
        // No in-app purchases exist for this build, so StoreKit returns an
        // empty catalogue. That must land on one readable line, and the screen
        // must stay alive.
        let vc = makeScreen()
        vc.applyStoreState(.unavailable("no products configured"))

        XCTAssertEqual(1, vc.tableView(vc.tableView, numberOfRowsInSection: 1),
                       "the unavailable state should be a single line, not a list")
        let row = cell(vc, 1, 0)
        XCTAssertEqual("supportStatus", row.accessibilityIdentifier)
        let content = row.contentConfiguration as? UIListContentConfiguration
        XCTAssertEqual("In-app support is not available on this device right now.", content?.text)
        XCTAssertEqual(.none, row.selectionStyle, "the status line must not look tappable")
    }

    func testReadyShowsOneRowPerTierWithTheStoresOwnPrice() {
        let vc = makeScreen()
        vc.applyStoreState(.ready([
            SupportTier(id: SupportCatalogue.oneCoffee, label: "☕  One Coffee", price: "¥300"),
            SupportTier(id: SupportCatalogue.twoCoffees, label: "☕☕  Two Coffees", price: "¥600"),
            SupportTier(id: SupportCatalogue.boost, label: "🚀  Give Development a Boost", price: "¥1,000"),
        ]))

        XCTAssertEqual(3, vc.tableView(vc.tableView, numberOfRowsInSection: 1))
        let first = cell(vc, 1, 0)
        XCTAssertEqual("tier_tip_coffee_1", first.accessibilityIdentifier)
        let content = first.contentConfiguration as? UIListContentConfiguration
        XCTAssertEqual("☕  One Coffee", content?.text)
        XCTAssertEqual("¥300", content?.secondaryText, "the price must be the store's formatted string")
    }

    func testThanksReplacesTheTiersWithOneLine() {
        let vc = makeScreen()
        vc.applyStoreState(.thanks)
        XCTAssertEqual(1, vc.tableView(vc.tableView, numberOfRowsInSection: 1))
        let content = cell(vc, 1, 0).contentConfiguration as? UIListContentConfiguration
        XCTAssertEqual("Thank you for supporting mdr! ☕", content?.text)
    }
}
