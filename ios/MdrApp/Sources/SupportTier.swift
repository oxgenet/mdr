import Foundation
import StoreKit

/// One tip tier, priced by the App Store for the reader's storefront.
///
/// The counterpart of `Billing.Tier` on Android. `price` is whatever StoreKit
/// hands back as `displayPrice`, so it reads "¥300" in Japan and "$2.99"
/// elsewhere with no currency handling here.
struct SupportTier: Equatable {
    let id: String
    let label: String
    let price: String
}

/// Anything that can be shown as a tier. `Product` conforms as-is; tests use a
/// stub, because `Product` is a StoreKit value type that cannot be constructed
/// outside a real (or simulated) store.
protocol SupportProduct {
    var id: String { get }
    var displayName: String { get }
    var displayPrice: String { get }
    var price: Decimal { get }
}

extension Product: SupportProduct {}

/// The tip jar's catalogue: the IDs, their ordering, and how each one reads.
///
/// Mirrors the `companion object` of `Billing.kt`. The IDs must match the
/// in-app purchases in App Store Connect *and* the in-app products in the Play
/// Console exactly — the same three strings are used on both stores so the two
/// listings stay legible side by side. A typo surfaces at runtime only as
/// "in-app support is not available", which is indistinguishable from the
/// products simply not existing yet.
enum SupportCatalogue {
    static let oneCoffee = "tip_coffee_1"
    static let twoCoffees = "tip_coffee_2"
    static let boost = "tip_boost"

    static let productIDs = [oneCoffee, twoCoffees, boost]

    /// Emoji prefix for each tier, matching the Android wording.
    static func emoji(for productID: String) -> String {
        switch productID {
        case oneCoffee: return "☕"
        case twoCoffees: return "☕☕"
        case boost: return "🚀"
        default: return "★"
        }
    }

    /// Order tiers by what the store charges, cheapest first.
    ///
    /// StoreKit returns products in an unspecified order, and the three tiers
    /// only read as a ladder if they ascend. Sorting on the numeric `price`
    /// rather than the formatted string keeps that true in every currency.
    static func ladder(from products: [any SupportProduct]) -> [SupportTier] {
        products
            .sorted { $0.price < $1.price }
            .map { SupportTier(id: $0.id, label: "\(emoji(for: $0.id))  \($0.displayName)", price: $0.displayPrice) }
    }
}
