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
    fun theSupportSectionDegradesQuietlyWithoutConfiguredProducts() {
        // No in-app products exist for this build yet, so Play returns either a
        // connection failure or an empty catalogue. Both must land on the same
        // readable line, and the screen must stay alive.
        val expected = context.getString(R.string.support_unavailable)
        val loading = context.getString(R.string.support_loading)

        ActivityScenario.launch(SettingsActivity::class.java).use { scenario ->
            var status = loading
            val deadline = System.currentTimeMillis() + 15_000
            while (System.currentTimeMillis() < deadline && status == loading) {
                Thread.sleep(250)
                scenario.onActivity { a ->
                    status = a.findViewById<TextView>(R.id.support_status).text.toString()
                }
            }
            assertEquals("support section did not settle into the unavailable state", expected, status)

            // And no tier buttons were left behind.
            scenario.onActivity { a ->
                val tiers = a.findViewById<android.widget.LinearLayout>(R.id.tier_container)
                assertEquals(0, tiers.childCount)
            }
        }
    }
}
