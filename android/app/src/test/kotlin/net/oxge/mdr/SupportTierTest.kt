package net.oxge.mdr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The parts of the tip jar and preferences that are pure Kotlin.
 *
 * Anything touching `BillingClient` or `SharedPreferences` needs a device and
 * lives in `androidTest` instead.
 */
class SupportTierTest {

    @Test
    fun everyProductIdHasItsOwnEmoji() {
        // The emoji are how the three tiers read as a ladder at a glance, and
        // they have to match the iOS wording.
        assertEquals("☕", Billing.emojiFor(Billing.ONE_COFFEE))
        assertEquals("☕☕", Billing.emojiFor(Billing.TWO_COFFEES))
        assertEquals("🚀", Billing.emojiFor(Billing.BOOST))
    }

    @Test
    fun anUnknownProductStillGetsAMarker() {
        // A product added in the Play Console but not here must not render a
        // blank button.
        assertEquals("★", Billing.emojiFor("tip_something_new"))
        assertEquals("★", Billing.emojiFor(""))
    }

    @Test
    fun productIdsAreTheThreeAdvertisedTiers() {
        // These strings must match the in-app products in the Play Console
        // exactly; a typo shows up as "no products configured" at runtime.
        assertEquals(listOf("tip_coffee_1", "tip_coffee_2", "tip_boost"), Billing.PRODUCT_IDS)
        assertEquals(3, Billing.PRODUCT_IDS.distinct().size)
    }

    // --- language preference ---

    @Test
    fun langIndexRoundTripsEveryOfferedTag() {
        Billing.PRODUCT_IDS // keep both subjects in one place; no-op
        Prefs.LANG_TAGS.forEachIndexed { i, tag ->
            assertEquals("tag '$tag' did not map back to its own row", i, Prefs.langIndex(tag))
        }
    }

    @Test
    fun autoIsTheFirstLanguageOption() {
        assertEquals("", Prefs.LANG_TAGS.first())
        assertEquals(0, Prefs.langIndex(""))
    }

    @Test
    fun anUnknownLanguageTagFallsBackToAuto() {
        // The tag is persisted, so an upgrade that drops a language would
        // otherwise leave the spinner pointing at nothing.
        assertEquals(0, Prefs.langIndex("xx-YY"))
        assertEquals(0, Prefs.langIndex("de"))
    }

    @Test
    fun offeredLanguagesAreTheOnesTheCoreCanAct_on() {
        // core::core::lang understands exactly these; offering more would show
        // a setting that silently does nothing.
        assertTrue(Prefs.LANG_TAGS.containsAll(listOf("ja", "zh-Hans", "zh-Hant", "ko")))
        assertEquals(5, Prefs.LANG_TAGS.size)
    }
}
