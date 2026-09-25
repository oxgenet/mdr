package net.oxge.mdr

import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The config screen, including how the tip jar behaves when Play has nothing
 * to sell.
 *
 * That last part matters more than it sounds: until the in-app products are
 * live in the Play Console — and on any device without Play Services — the
 * support section is permanently in its unavailable state. It has to read as a
 * calm sentence, not a crash or an error dialog, because that is what every
 * tester will see first.
 */
@RunWith(AndroidJUnit4::class)
class SettingsActivityTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun clearPreferences() {
        context.getSharedPreferences("mdr", android.content.Context.MODE_PRIVATE)
            .edit().clear().commit()
    }

    @Test
    fun theScreenOpensWithEverySection() {
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                assertTrue("toc switch missing", a.findViewById<Switch>(R.id.toc_switch) != null)
                assertTrue("language picker missing", a.findViewById<Spinner>(R.id.lang_spinner) != null)
                assertTrue("support status missing", a.findViewById<TextView>(R.id.support_status) != null)
                assertTrue("about line missing", a.findViewById<TextView>(R.id.about_version) != null)
            }
        }
    }

    @Test
    fun theAboutLineShowsTheLoadedCoreVersion() {
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                val text = a.findViewById<TextView>(R.id.about_version).text.toString()
                assertTrue(
                    "about line '$text' does not contain the core version '${MdrCore.version}'",
                    MdrCore.version.isNotEmpty() && text.contains(MdrCore.version),
                )
            }
        }
    }

    @Test
    fun theAboutSectionCarriesTheUpstreamAttribution() {
        // MIT obliges a derivative work to carry the original copyright notice.
        // The mobile shells were the only place it had been dropped; this pins
        // it so it cannot quietly disappear again. Mirrors the iOS test
        // SettingsTests.testAboutCarriesTheUpstreamAttribution.
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                val ours = a.findViewById<TextView>(R.id.about_copyright).text.toString()
                val upstream = a.findViewById<TextView>(R.id.about_upstream).text.toString()
                assertTrue("fork copyright missing: '$ours'", ours.contains("Opusify"))
                assertTrue("upstream notice missing: '$upstream'", upstream.contains("Clever Cloud"))
                assertTrue("upstream notice must name the licence: '$upstream'", upstream.contains("MIT"))
            }
        }
    }

    @Test
    fun togglingTheTocSwitchPersists() {
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                assertFalse("should default to off", Prefs.from(a).showToc)
                a.findViewById<Switch>(R.id.toc_switch).performClick()
                assertTrue("switch did not reach preferences", Prefs.from(a).showToc)
            }
        }
        // A second launch reads it back from disk, which is what MainActivity
        // does on resume.
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                assertTrue(a.findViewById<Switch>(R.id.toc_switch).isChecked)
            }
        }
    }

    @Test
    fun choosingALanguagePersistsItsTag() {
        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                a.findViewById<Spinner>(R.id.lang_spinner).setSelection(Prefs.langIndex("zh-Hant"))
            }
        }
        assertEquals("zh-Hant", Prefs.from(context).lang)
    }

    @Test
    fun theSupportSectionAlwaysSettlesIntoATerminalState() {
        // Whether Play has anything to sell depends on the products being live
        // and on this build being one Play recognises, so both outcomes are
        // legitimate here. What must always hold is that the section stops
        // loading and lands somewhere readable: either the calm unavailable
        // line with no buttons, or priced tiers. Staying on "Loading…" forever
        // is the failure worth catching, and the screen must survive either way.
        val unavailable = context.getString(R.string.support_unavailable)
        val loading = context.getString(R.string.support_loading)

        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            var status = loading
            var statusShown = true
            var tiers = 0
            // Generous: this waits on Play Services over the network, and an
            // emulator is slower than a phone.
            val deadline = System.currentTimeMillis() + 45_000
            // Settled means either tiers appeared, or the status line is still
            // showing but no longer says "Loading…". Reading the text alone is
            // not enough: on success the status view is hidden rather than
            // relabelled, so its text stays at whatever it last displayed.
            fun settled() = tiers > 0 || !statusShown || status != loading
            while (System.currentTimeMillis() < deadline && !settled()) {
                Thread.sleep(250)
                scenario.onActivity { a ->
                    val statusView = a.findViewById<TextView>(R.id.support_status)
                    status = statusView.text.toString()
                    statusShown = statusView.visibility == android.view.View.VISIBLE
                    tiers = a.findViewById<android.widget.LinearLayout>(R.id.tier_container).childCount
                }
            }

            assertTrue("support section never stopped loading", settled())
            if (tiers == 0) {
                assertEquals("no tiers, so the unavailable line must be showing", unavailable, status)
            } else {
                assertTrue("tiers are showing, so nothing should be queued", tiers in 1..3)
            }
        }
    }
}
