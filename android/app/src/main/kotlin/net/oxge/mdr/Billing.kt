package net.oxge.mdr

import android.app.Activity
import android.os.Handler
import android.os.Looper
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

    /**
     * One tip tier, priced by Play for the user's storefront.
     *
     * [offerToken] identifies which purchase option of the product is being
     * bought. Products created under Play's newer one-time-product model carry
     * their price on a purchase option rather than on the product itself, and
     * the purchase flow has to name the one it means.
     */
    data class Tier(
        val id: String,
        val label: String,
        val price: String,
        val details: ProductDetails,
        val offerToken: String?,
    )

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

    private val timeout = Handler(Looper.getMainLooper())
    private var settled = false

    /** Publish a state, and remember once we have reached a terminal one. */
    private fun emit(state: State) {
        Log.i(TAG, "state -> ${state.javaClass.simpleName}")
        if (state !is State.Loading) {
            settled = true
            timeout.removeCallbacksAndMessages(null)
        }
        onState(state)
    }

    fun start() {
        Log.i(TAG, "start(): connecting")
        emit(State.Loading)
        // Neither startConnection nor queryProductDetailsAsync is guaranteed to
        // call back: Play Services can be absent, not signed in, or simply
        // wedged, and then nothing arrives at all. Without this the section
        // sits on "Loading…" for as long as the screen is open.
        timeout.postDelayed(
            { Log.w(TAG, "timeout fired; settled=$settled"); if (!settled) emit(State.Unavailable("Play did not respond")) },
            RESPONSE_TIMEOUT_MS,
        )
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    emit(State.Unavailable(result.debugMessage.ifBlank { "code ${result.responseCode}" }))
                    return
                }
                queryTiers()
            }

            override fun onBillingServiceDisconnected() {
                emit(State.Unavailable("disconnected from Play"))
            }
        })
    }

    fun stop() {
        timeout.removeCallbacksAndMessages(null)
        client.endConnection()
    }

    private fun queryTiers() {
        val products = PRODUCT_IDS.map {
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(it)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder().setProductList(products).build()
        // Billing 8 hands back a QueryProductDetailsResult rather than a bare
        // list, which also reports the products Play could not resolve.
        client.queryProductDetailsAsync(params) { result, queryResult ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                emit(State.Unavailable(result.debugMessage.ifBlank { "code ${result.responseCode}" }))
                return@queryProductDetailsAsync
            }
            val details = queryResult.productDetailsList
            // Naming the unresolved ids turns the commonest setup mistake — a
            // product id here not matching the Play Console exactly — into
            // something diagnosable instead of a blank support section.
            queryResult.unfetchedProductList.forEach {
                Log.w(TAG, "Play did not return product '${it.productId}': ${it.statusCode}")
            }
            if (details.isEmpty()) {
                // The products are not live in the Play Console yet, or this
                // build is not on a track Play recognises.
                emit(State.Unavailable("no products configured"))
                return@queryProductDetailsAsync
            }
            emit(State.Ready(sortTiers(details)))
        }
    }

    /** Launch Play's purchase sheet for one tier. */
    fun buy(tier: Tier) {
        val product = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(tier.details)
            .apply {
                // Required for a product priced through a purchase option;
                // absent for one carrying its price directly, where passing a
                // blank token would be rejected.
                tier.offerToken?.takeIf { it.isNotBlank() }?.let { setOfferToken(it) }
            }
            .build()
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(product))
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
            activity.runOnUiThread { emit(State.Thanks) }
        }
    }

    companion object {
        private const val TAG = "mdr-billing"

        /** How long to wait for Play before declaring the tip jar unavailable. */
        private const val RESPONSE_TIMEOUT_MS = 12_000L

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
            details.mapNotNull { product -> product to offerFor(product) }
                .sortedBy { (_, offer) -> offer?.priceAmountMicros ?: Long.MAX_VALUE }
                .map { (product, offer) ->
                    Tier(
                        id = product.productId,
                        label = "${emojiFor(product.productId)}  ${product.name}",
                        price = offer?.formattedPrice.orEmpty(),
                        details = product,
                        offerToken = offer?.offerToken,
                    )
                }

        /**
         * The purchase option to charge for, preferring the list Play returns
         * for products defined with purchase options and falling back to the
         * price carried directly on older products. A tip has exactly one
         * option, so the first is the right one.
         */
        private fun offerFor(product: ProductDetails): ProductDetails.OneTimePurchaseOfferDetails? =
            product.oneTimePurchaseOfferDetailsList?.firstOrNull()
                ?: product.oneTimePurchaseOfferDetails
    }
}
