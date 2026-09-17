package net.oxge.mdr

import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * End-to-end: Activity → JNI → Rust core → WebView.
 *
 * The unit tests prove each piece; this proves they are actually wired
 * together, which is the failure the others cannot see — a page that renders
 * perfectly in Rust but never reaches the screen.
 */
@RunWith(AndroidJUnit4::class)
class ViewerFlowTest {

    @Test
    fun theWelcomeDocumentReachesTheWebView() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val heading = evalWhenReady(scenario, "document.querySelector('.content h1').textContent")
            assertEquals("\"mdr\"", heading)
        }
    }

    @Test
    fun theRenderedPageCarriesTheMdrChrome() {
        // The TOC sidebar and the search hook are what the native menu drives;
        // if the page ever stopped shipping them, the menu would silently do
        // nothing rather than fail.
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val hasSidebar = evalWhenReady(scenario, "!!document.querySelector('.sidebar')")
            assertEquals("true", hasSidebar)
            val hasSearch = evalWhenReady(scenario, "typeof window.mdrSearch")
            assertEquals("\"function\"", hasSearch)
        }
    }

    @Test
    fun searchHighlightsMatchesInTheRenderedPage() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            // "Markdown" appears in the welcome text; mdrSearch returns a count.
            val count = evalWhenReady(scenario, "window.mdrSearch('Markdown')")
            assertTrue("expected at least one match, got $count", (count?.toIntOrNull() ?: 0) >= 1)
        }
    }

    // --- helpers ---

    /** The Activity sets the WebView as its whole content view. */
    private fun webViewOf(scenario: ActivityScenario<MainActivity>): WebView {
        lateinit var web: WebView
        scenario.onActivity { activity ->
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            web = content.getChildAt(0) as WebView
        }
        return web
    }

    /**
     * Poll [script] until the page has loaded and it returns something useful.
     *
     * `loadDataWithBaseURL` is asynchronous and there is no navigation callback
     * to hang off here, so polling is the honest way to wait. Returns the raw
     * JSON `evaluateJavascript` produced (so `"mdr"` keeps its quotes).
     */
    private fun evalWhenReady(scenario: ActivityScenario<MainActivity>, script: String): String? {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        var last: String? = null
        while (System.currentTimeMillis() < deadline) {
            if (eval(scenario, "document.readyState") == "\"complete\"") {
                last = eval(scenario, script)
                if (last != null && last != "null") return last
            }
            Thread.sleep(POLL_MS)
        }
        return last
    }

    private fun eval(scenario: ActivityScenario<MainActivity>, script: String): String? {
        val latch = CountDownLatch(1)
        var result: String? = null
        val web = webViewOf(scenario)
        scenario.onActivity {
            web.evaluateJavascript(script) { value ->
                result = value
                latch.countDown()
            }
        }
        latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)
        return result
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val POLL_MS = 250L
    }
}
