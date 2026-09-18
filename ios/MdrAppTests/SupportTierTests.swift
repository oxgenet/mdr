import XCTest
@testable import MdrApp

/// The parts of the tip jar and preferences that are pure Swift.
///
/// Mirrors `SupportTierTest` on Android case for case. Anything that needs a
/// real (or simulated) store lives in `StoreTests`; anything that needs a view
/// lives in `SettingsTests`.
final class SupportTierTests: XCTestCase {

    /// `Product` is a StoreKit value type that cannot be built outside a store,
    /// so the ordering logic is exercised through the protocol it consumes.
    private struct StubProduct: SupportProduct {
        let id: String
        let displayName: String
        let displayPrice: String
        let price: Decimal
    }

    func testEveryProductIDHasItsOwnEmoji() {
        // The emoji are how the three tiers read as a ladder at a glance, and
        // they have to match the Android wording.
        XCTAssertEqual("☕", SupportCatalogue.emoji(for: SupportCatalogue.oneCoffee))
        XCTAssertEqual("☕☕", SupportCatalogue.emoji(for: SupportCatalogue.twoCoffees))
        XCTAssertEqual("🚀", SupportCatalogue.emoji(for: SupportCatalogue.boost))
    }

    func testAnUnknownProductStillGetsAMarker() {
        // A product added in App Store Connect but not here must not render a
        // blank row.
        XCTAssertEqual("★", SupportCatalogue.emoji(for: "tip_something_new"))
        XCTAssertEqual("★", SupportCatalogue.emoji(for: ""))
    }

    func testProductIDsAreTheThreeAdvertisedTiers() {
        // These strings must match the in-app purchases in App Store Connect
        // exactly — and the Play Console products, which use the same three IDs.
        XCTAssertEqual(["tip_coffee_1", "tip_coffee_2", "tip_boost"], SupportCatalogue.productIDs)
        XCTAssertEqual(3, Set(SupportCatalogue.productIDs).count)
    }

    func testTiersAreOrderedCheapestFirstRegardlessOfStoreOrder() {
        // StoreKit does not promise an order, and the ladder only reads as a
        // ladder if it ascends.
        let shuffled: [any SupportProduct] = [
            StubProduct(id: SupportCatalogue.boost, displayName: "Give Development a Boost",
                        displayPrice: "¥1,000", price: 1000),
            StubProduct(id: SupportCatalogue.oneCoffee, displayName: "One Coffee",
                        displayPrice: "¥300", price: 300),
            StubProduct(id: SupportCatalogue.twoCoffees, displayName: "Two Coffees",
                        displayPrice: "¥600", price: 600),
        ]
        let ladder = SupportCatalogue.ladder(from: shuffled)
        XCTAssertEqual(
            [SupportCatalogue.oneCoffee, SupportCatalogue.twoCoffees, SupportCatalogue.boost],
            ladder.map(\.id)
        )
        XCTAssertEqual("☕  One Coffee", ladder[0].label)
        // The price shown is the store's formatted string, never a hardcoded
        // amount — that is what makes the screen right outside Japan.
        XCTAssertEqual("¥300", ladder[0].price)
    }

    func testTheLadderSortsByPriceNotByFormattedString() {
        // "¥1,000" sorts before "¥300" as text. The numeric price must win.
        let products: [any SupportProduct] = [
            StubProduct(id: SupportCatalogue.boost, displayName: "Boost", displayPrice: "¥1,000", price: 1000),
            StubProduct(id: SupportCatalogue.oneCoffee, displayName: "One", displayPrice: "¥300", price: 300),
        ]
        XCTAssertEqual([SupportCatalogue.oneCoffee, SupportCatalogue.boost],
                       SupportCatalogue.ladder(from: products).map(\.id))
    }

    // MARK: - language preference

    func testLangIndexRoundTripsEveryOfferedTag() {
        for (i, tag) in Prefs.langTags.enumerated() {
            XCTAssertEqual(i, Prefs.langIndex(tag), "tag '\(tag)' did not map back to its own row")
        }
    }

    func testAutoIsTheFirstLanguageOption() {
        XCTAssertEqual("", Prefs.langTags.first)
        XCTAssertEqual(0, Prefs.langIndex(""))
    }

    func testAnUnknownLanguageTagFallsBackToAuto() {
        // The tag is persisted, so an upgrade that drops a language would
        // otherwise leave the picker pointing at nothing.
        XCTAssertEqual(0, Prefs.langIndex("xx-YY"))
        XCTAssertEqual(0, Prefs.langIndex("de"))
    }

    func testOfferedLanguagesAreTheOnesTheCoreCanActOn() {
        // core::lang understands exactly these; offering more would show a
        // setting that silently does nothing.
        for tag in ["ja", "zh-Hans", "zh-Hant", "ko"] {
            XCTAssertTrue(Prefs.langTags.contains(tag), "\(tag) is not offered")
        }
        XCTAssertEqual(5, Prefs.langTags.count)
    }

    /// Not on the Android side, because only iOS can check it cheaply here:
    /// every offered tag must survive a round trip through the rendering core.
    /// A picker row whose tag the core ignores is a setting that does nothing.
    func testEveryOfferedTagIsHonouredByTheCore() {
        for tag in Prefs.langTags where !tag.isEmpty {
            let html = MdrCore.renderPage(markdown: "# t", baseDir: "", lang: tag)
            XCTAssertTrue(
                html.contains("<html lang=\"\(tag)\">"),
                "the core did not honour the offered tag '\(tag)'"
            )
        }
    }

    // MARK: - persistence

    func testPreferencesPersistAndDefaultSafely() throws {
        let name = "mdr.tests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let prefs = Prefs(defaults: suite)

        XCTAssertFalse(prefs.showToc, "the sidebar should default to off, as on Android")
        XCTAssertEqual("", prefs.lang, "language should default to auto-detect")

        prefs.showToc = true
        prefs.lang = "zh-Hant"
        // Read back through a second instance, which is what the viewer does
        // when it returns from Settings.
        let reread = Prefs(defaults: suite)
        XCTAssertTrue(reread.showToc)
        XCTAssertEqual("zh-Hant", reread.lang)
    }
}
