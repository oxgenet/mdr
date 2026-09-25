import XCTest
import StoreKit
import StoreKitTest
@testable import MdrApp

/// The purchase path, against a simulated App Store.
///
/// This is the one thing the Android side could not do. Play only returns
/// products to a build it has already seen, so `Billing.kt` is unverified until
/// an AAB reaches internal testing. `SKTestSession` has no such restriction:
/// it serves `Mdr.storekit` locally, so the catalogue, the purchase, the
/// verification and the finish all run here — before anything is uploaded.
///
/// What it does not prove: that the three product IDs exist in App Store
/// Connect. Nothing local can prove that; `Mdr.storekit` is a local file and
/// would happily serve IDs that were never created. `SupportTierTests` pins the
/// strings, and the first sandbox purchase is what confirms the rest.
@MainActor
final class StoreTests: XCTestCase {

    private var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()
        session = try SKTestSession(configurationFileNamed: "Mdr")
        session.resetToDefaultState()
        session.clearTransactions()
        // Buy without a confirmation sheet; the sheet is Apple's UI, not ours.
        session.askToBuyEnabled = false
        session.disableDialogs = true
    }

    /// Fail fast, and legibly, when the local store is not attached.
    ///
    /// Running these from the command line on Xcode 26 does **not** attach the
    /// StoreKit configuration: `xcodebuild` ignores the test plan's
    /// `storeKitConfigurationFileReference` (pointing it at a file that does
    /// not exist raises no error), and storekitd then answers from the real
    /// Media API — the simulator log shows "Requesting products from Media API"
    /// followed by "Ignoring empty product response". `SKTestSession` on its
    /// own reports `notEntitled`.
    ///
    /// From Xcode's own test runner the configuration *is* applied and these
    /// run for real, which is why they are written rather than deleted. They
    /// skip rather than fail so a headless run stays honest: a green tick here
    /// would claim the purchase path was covered when it was not.
    private func requireLocalStore() async throws -> [SupportTier] {
        let store = Store()
        await store.loadProducts()
        guard case .ready(let tiers) = store.state else {
            throw XCTSkip(
                """
                The local StoreKit configuration is not attached, so the purchase path                 cannot be exercised here (store said: \(store.state)).

                Run these from Xcode: open ios/MdrApp/MdrApp.xcodeproj, pick the MdrApp                 scheme and press Cmd-U. The scheme and MdrApp.xctestplan both reference                 Mdr.storekit; Xcode applies it, plain xcodebuild does not.
                """
            )
        }
        self.loadedStore = store
        return tiers
    }

    private var loadedStore: Store?

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    func testTheCatalogueLoadsAllThreeTiersInPriceOrder() async throws {
        let tiers = try await requireLocalStore()
        XCTAssertEqual(
            [SupportCatalogue.oneCoffee, SupportCatalogue.twoCoffees, SupportCatalogue.boost],
            tiers.map(\.id)
        )
        // Every tier shows a price StoreKit formatted, not a hardcoded one.
        for tier in tiers {
            XCTAssertFalse(tier.price.isEmpty, "\(tier.id) came back with no display price")
        }
    }

    func testBuyingATierCompletesAndThanksTheSupporter() async throws {
        let tiers = try await requireLocalStore()
        let store = try XCTUnwrap(loadedStore)
        await store.buy(try XCTUnwrap(tiers.first))
        XCTAssertEqual(.thanks, store.state, "a completed tip should thank the supporter")
    }

    /// The consumable rule, and the reason `finish()` is not optional.
    ///
    /// An unfinished consumable is redelivered on every launch and cannot be
    /// bought again — the iOS counterpart of Android's unconsumed purchase. If
    /// `settle` ever stopped finishing transactions, this is what would catch
    /// it: the second purchase would not be possible, and the unfinished one
    /// would still be sitting in the queue.
    func testATipCanBeGivenMoreThanOnceAndNothingIsLeftUnfinished() async throws {
        let tiers = try await requireLocalStore()
        let store = try XCTUnwrap(loadedStore)
        await store.buy(try XCTUnwrap(tiers.first))
        XCTAssertEqual(.thanks, store.state)

        // Tip again with the same tier. A consumable that was properly finished
        // is purchasable once more; one that was not would fail here.
        store.showTiersAgain()
        guard case .ready(let again) = store.state, let secondCoffee = again.first else {
            return XCTFail("tiers did not come back after a thank-you")
        }
        await store.buy(secondCoffee)
        XCTAssertEqual(.thanks, store.state, "a supporter must be able to tip more than once")

        // And nothing is left unfinished in the queue.
        var unfinished: [String] = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                unfinished.append(transaction.productID)
            }
        }
        XCTAssertTrue(
            unfinished.isEmpty,
            "unfinished consumables would be redelivered forever and block re-purchase: \(unfinished)"
        )
    }

    /// Nothing is unlocked in return for a tip. That is what keeps these
    /// donations rather than paid features, on both stores.
    func testATipUnlocksNothing() async throws {
        let tiers = try await requireLocalStore()
        let store = try XCTUnwrap(loadedStore)
        await store.buy(try XCTUnwrap(tiers.last))

        // Consumables never appear in current entitlements; if one did, it
        // would mean a tier had been created as a non-consumable by mistake.
        var entitled: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                entitled.append(transaction.productID)
            }
        }
        XCTAssertTrue(entitled.isEmpty, "a tip must not grant an entitlement, got \(entitled)")
    }

    /// A store failure has to land on the calm line rather than an error.
    ///
    /// This goes through `buy`'s own guard rather than a simulated StoreKit
    /// failure, because both simulated variants proved unusable. Failing the
    /// *catalogue* is vacuous once any earlier test has loaded it — StoreKit
    /// caches `Product.products(for:)` for the process, so the error is never
    /// consulted, and test order decides whether the assertion means anything.
    /// Failing the *purchase* hangs: `product.purchase()` wants a UI scene to
    /// anchor its sheet to, and a unit test hosted in the app has none, so the
    /// await never returns and takes the whole suite down with it.
    ///
    /// The guard below reaches the same `.unavailable` state by the same line
    /// of code, deterministically and in microseconds.
    func testBuyingATierTheStoreDoesNotKnowDegradesToTheQuietLine() async {
        let store = Store()
        await store.buy(SupportTier(id: "tip_not_a_real_product", label: "x", price: "¥1"))
        guard case .unavailable = store.state else {
            return XCTFail("an unknown product must degrade quietly, got \(store.state)")
        }
    }
}
