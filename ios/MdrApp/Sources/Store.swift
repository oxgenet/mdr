import Foundation
import StoreKit

/// The tip jar, over StoreKit 2.
///
/// The counterpart of `Billing.kt`. Apple's rules match Google's here: an
/// in-app support payment has to go through in-app purchase, so there is
/// deliberately no link out to Ko-fi, PayPal or GitHub Sponsors.
///
/// All three tiers are **consumable**: a tip can be given more than once, and
/// nothing is unlocked in return, which is what keeps this a donation rather
/// than a paid feature. On iOS the equivalent of Android's "consume" step is
/// `Transaction.finish()` — an unfinished consumable is redelivered on every
/// launch and cannot be bought again, so it has to run for every transaction,
/// including ones that arrive from a previous session.
@MainActor
final class Store {

    /// What the settings screen should currently show. Mirrors
    /// `Billing.State` case for case.
    enum State: Equatable {
        /// Asking the App Store for the catalogue.
        case loading
        /// Tiers are ready to display, in ascending price order.
        case ready([SupportTier])
        /// In-app purchase is not usable here. Expected before the products
        /// exist in App Store Connect, on a device with purchases restricted,
        /// and whenever the store cannot be reached — so it must render as a
        /// calm line, not an error dialog.
        case unavailable(String)
        /// A tip completed.
        case thanks
    }

    private(set) var state: State = .loading {
        didSet { onState?(state) }
    }

    /// Called on the main actor whenever ``state`` changes.
    var onState: ((State) -> Void)?

    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    init() {}

    deinit {
        updatesTask?.cancel()
        loadTask?.cancel()
    }

    /// Begin listening for transactions and load the catalogue.
    func start() {
        state = .loading

        // Transactions can arrive outside a purchase call: an Ask to Buy
        // approval, a purchase made on another device, or one this app failed
        // to finish last time. Android handles the same case in `finish()`.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.settle(update)
            }
        }

        loadTask = Task { [weak self] in
            await self?.loadProducts()
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        loadTask?.cancel()
        loadTask = nil
    }

    /// Fetch the three tiers. Exposed for tests, which drive it directly.
    func loadProducts() async {
        do {
            let found = try await Product.products(for: SupportCatalogue.productIDs)
            guard !found.isEmpty else {
                // The in-app purchases are not live in App Store Connect yet,
                // or this build is not one the store recognises.
                state = .unavailable("no products configured")
                return
            }
            products = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
            state = .ready(SupportCatalogue.ladder(from: found))
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// Present Apple's purchase sheet for one tier.
    func buy(_ tier: SupportTier) async {
        guard let product = products[tier.id] else {
            state = .unavailable("unknown product \(tier.id)")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await settle(verification)
            case .userCancelled:
                // Not a failure. Leave the tiers on screen so another tier —
                // or the same one again — is still one tap away.
                break
            case .pending:
                // Ask to Buy, or a payment awaiting approval. The result
                // arrives through Transaction.updates instead.
                break
            @unknown default:
                break
            }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// Verify, finish, and thank.
    ///
    /// An unverified transaction is deliberately *not* finished: finishing it
    /// would consume a purchase whose signature did not check out.
    private func settle(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            await transaction.finish()
            state = .thanks
        case .unverified(_, let error):
            state = .unavailable(error.localizedDescription)
        }
    }

    /// Restore the tier list after a thank-you, so a supporter can tip again.
    /// Consumables are never "owned", so this is just re-showing the ladder.
    func showTiersAgain() {
        guard !products.isEmpty else { return }
        state = .ready(SupportCatalogue.ladder(from: Array(products.values)))
    }
}
