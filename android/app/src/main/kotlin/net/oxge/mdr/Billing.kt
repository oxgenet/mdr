package net.oxge.mdr

import android.app.Activity
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams

/**
 * The tip jar, over Google Play Billing.
 *
 * Google Play's payments policy requires in-app support payments to go through
 * Play Billing — a link out to Ko-fi or PayPal would risk removal, so there is
 * deliberately no such fallback here.
 *
 * All three tiers are **consumable**: a tip can be given more than once, so
 * each purchase is consumed immediately after it completes, which returns the
 * product to a purchasable state. Nothing is unlocked in return, which is what
 * keeps this a donation rather than a paid feature.
 */
class Billing(
    private val activity: Activity,
    private val onState: (State) -> Unit,
) {

    /** What the settings screen should currently show. */
    sealed interface State {
        /** Connecting, or querying the catalogue. */
        object Loading : State
        /** Tiers are ready to display, in ascending price order. */
        data class Ready(val tiers: List<Tier>) : State
        /**
         * Billing is not usable here. Expected on an emulator without Play
         * Store, on a build Play does not know about, and before the products
         * exist in the Play Console — so it must render as a calm message,
         * not an error.
         */
        data class Unavailable(val reason: String) : State
        /** A tip completed. */
        object Thanks : State
    }

    /** One tip tier, priced by Play for the user's storefront. */
    data class Tier(val id: String, val label: String, val price: String, val details: ProductDetails)

    private val purchasesUpdated = PurchasesUpdatedListener { result, purchases ->
        when {
            result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null ->
                purchases.forEach { finish(it) }
            result.responseCode == BillingClient.BillingResponseCode.USER_CANCELED ->
                Log.i(TAG, "tip cancelled by user")
            else ->
                Log.w(TAG, "purchase failed: ${result.responseCode} ${result.debugMessage}")
        }
    }

    private val client: BillingClient = BillingClient.newBuilder(activity)
        .setListener(purchasesUpdated)
        // The no-argument form is deprecated in Billing 7 and gone in 8. Tips
        // are one-time products, so that is all this has to declare.
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build(),
        )
        .build()

    fun start() {
        onState(State.Loading)
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    onState(State.Unavailable(result.debugMessage.ifBlank { "code ${result.responseCode}" }))
                    return
                }
                queryTiers()
            }

            override fun onBillingServiceDisconnected() {
                onState(State.Unavailable("disconnected from Play"))
            }
        })
    }

    fun stop() = client.endConnection()

    private fun queryTiers() {
        val products = PRODUCT_IDS.map {
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(it)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder().setProductList(products).build()
        client.queryProductDetailsAsync(params) { result, details ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                onState(State.Unavailable(result.debugMessage.ifBlank { "code ${result.responseCode}" }))
                return@queryProductDetailsAsync
            }
            if (details.isEmpty()) {
                // The products are not live in the Play Console yet, or this
                // build is not on a track Play recognises.
                onState(State.Unavailable("no products configured"))
                return@queryProductDetailsAsync
            }
            onState(State.Ready(sortTiers(details)))
        }
    }

    /** Launch Play's purchase sheet for one tier. */
    fun buy(tier: Tier) {
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(tier.details)
                        .build(),
                ),
            )
            .build()
        val result = client.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            Log.w(TAG, "could not start purchase: ${result.debugMessage}")
        }
    }

    /**
     * Acknowledge and consume a completed tip.
     *
     * Play refunds any purchase left unacknowledged for three days, and an
     * unconsumed consumable cannot be bought again — so this has to run for
     * every purchase, including ones that arrive from a previous session.
     */
    private fun finish(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (!purchase.isAcknowledged) {
            client.acknowledgePurchase(
                AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build(),
            ) { Log.i(TAG, "acknowledged: ${it.responseCode}") }
        }
        client.consumeAsync(
            ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build(),
        ) { result, _ ->
            Log.i(TAG, "consumed: ${result.responseCode}")
            activity.runOnUiThread { onState(State.Thanks) }
        }
    }

    companion object {
        private const val TAG = "mdr-billing"

        /**
         * Product IDs, which must match the in-app products created in the Play
         * Console exactly. Prices live there, not here: Play returns a
         * localised `formattedPrice` per storefront, so hardcoding "¥300" would
         * be wrong everywhere outside Japan.
         */
        const val ONE_COFFEE = "tip_coffee_1"
        const val TWO_COFFEES = "tip_coffee_2"
        const val BOOST = "tip_boost"

        val PRODUCT_IDS = listOf(ONE_COFFEE, TWO_COFFEES, BOOST)

        /** Emoji prefix for each tier, matching the iOS wording. */
        fun emojiFor(productId: String): String = when (productId) {
            ONE_COFFEE -> "☕"
            TWO_COFFEES -> "☕☕"
            BOOST -> "🚀"
            else -> "★"
        }

        /**
         * Order tiers by what Play charges, cheapest first.
         *
         * Play returns products in an unspecified order, and the three tiers
         * only read as a ladder if they ascend. Sorting on the raw micros
         * rather than the formatted string keeps that true in every currency.
         */
        fun sortTiers(details: List<ProductDetails>): List<Tier> =
            details.sortedBy { it.oneTimePurchaseOfferDetails?.priceAmountMicros ?: Long.MAX_VALUE }
                .map {
                    Tier(
                        id = it.productId,
                        label = "${emojiFor(it.productId)}  ${it.name}",
                        price = it.oneTimePurchaseOfferDetails?.formattedPrice.orEmpty(),
                        details = it,
                    )
                }
    }
}
