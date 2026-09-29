package net.oxge.mdr

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Renders the shared end-to-end fixtures through JNI on a device.
 *
 * These are the same documents `tests/fixtures.rs` renders on the desktop —
 * they ride into the test APK from `tests/samples/e2e` rather than being
 * copied, so the two suites cannot drift apart. What is proved here is the
 * Android path specifically: real files on a real filesystem, images resolved
 * from a real directory, and strings crossing the JNI boundary at the size a
 * genuine document reaches.
 *
 * Several fixtures are deliberately malformed. Surviving them is the point.
 */
@RunWith(AndroidJUnit4::class)
class FixtureRenderTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val assets get() = InstrumentationRegistry.getInstrumentation().context.assets

    /** Fixtures unpacked to a real directory, so relative images resolve. */
    private lateinit var dir: File

    @Before
    fun unpackFixtures() {
        dir = File(context.cacheDir, "fixtures").apply { deleteRecursively(); mkdirs() }
        copyAsset("", dir)
    }

    private fun copyAsset(path: String, into: File) {
        val entries = assets.list(path).orEmpty()
        if (entries.isEmpty()) {
            // A leaf: copy the file itself.
            File(into, path.substringAfterLast('/')).outputStream().use { out ->
                assets.open(path).use { it.copyTo(out) }
            }
            return
        }
        for (entry in entries) {
            val child = if (path.isEmpty()) entry else "$path/$entry"
            // Directories report children; files do not.
            if (assets.list(child).orEmpty().isEmpty()) {
                File(into, entry).outputStream().use { out ->
                    assets.open(child).use { it.copyTo(out) }
                }
            } else {
                copyAsset(child, File(into, entry).apply { mkdirs() })
            }
        }
    }

    private fun render(name: String): String {
        val file = File(dir, name)
        assertTrue("fixture $name was not unpacked", file.exists())
        return MdrCore.renderPage(file.readText(), dir.absolutePath)
    }

    /**
     * Just the rendered document, without the surrounding chrome.
     *
     * The page also embeds the untouched source in the editor `<textarea>`, so
     * searching the whole page cannot distinguish "this was rendered" from
     * "this was offered for editing" — front matter belongs in the second.
     */
    private fun bodyOf(html: String): String {
        val start = html.indexOf("""<div class="content">""")
        val end = html.indexOf("""<div id="kebab">""", start)
        assertTrue("page structure changed; body could not be isolated", start >= 0 && end > start)
        return html.substring(start, end)
    }

    @Test
    fun everyFixtureRendersCompletely() {
        val fixtures = dir.listFiles { f -> f.extension == "md" }.orEmpty()
        assertTrue("no fixtures were unpacked", fixtures.size >= 4)
        for (file in fixtures) {
            val html = MdrCore.renderPage(file.readText(), dir.absolutePath)
            assertTrue("${file.name}: no page produced", html.contains("<html"))
            assertTrue("${file.name}: page was truncated", html.contains("</html>"))
            assertTrue("${file.name}: suspiciously small (${html.length})", html.length > 5_000)
        }
    }

    @Test
    fun frontMatterIsStrippedAndItsLanguageWins() {
        // Only CJK tags mean anything to the core's language resolution, so the
        // fixture declares zh-Hant — which detection would never pick for a
        // mostly-English document that happens to contain Japanese and Korean.
        val html = render("markdown.md")
        assertTrue("front matter lang ignored", html.contains("""<html lang="zh-Hant">"""))
        // Stripped from the rendered document, but still present in the editor
        // pane, which holds the real source and must not lose it.
        assertFalse(
            "front matter was rendered into the document body",
            bodyOf(html).contains("author: mdr test suite"),
        )
        assertTrue("the editor lost the front matter", html.contains("author: mdr test suite"))
    }

    @Test
    fun localImagesEmbedAndBadOnesDoNot() {
        val html = render("images.md")
        assertTrue("a valid local PNG was not embedded", html.contains("data:image/png;base64,"))
        assertTrue("a mislabelled image was embedded", html.contains("Invalid image"))
        assertTrue("a missing image was altered", html.contains("""src="assets/nope.png""""))
    }

    @Test
    fun theRemoteImagePolicyHoldsOnDevice() {
        val html = render("images.md")
        assertTrue("https should be allowed", html.contains("""src="https://example.com/chart.png""""))
        assertTrue("private http should be allowed", html.contains("""src="http://192.168.1.10/photo.png""""))
        assertFalse("public http should be blocked", html.contains("""src="http://example.com/insecure.png""""))
        assertTrue("blocked images should become placeholders", html.contains("img-blocked"))
    }

    @Test
    fun everyMermaidBlockIsProcessed() {
        val html = render("diagrams.md")
        assertFalse(
            "a mermaid block was left unprocessed",
            html.contains("""class="language-mermaid""""),
        )
        assertTrue(
            "no diagram was produced",
            html.contains("mermaid-diagram") || html.contains("""class="mermaid""""),
        )
        assertTrue("the document stopped at a broken diagram", html.contains("Gantt"))
    }

    @Test
    fun linksSurviveRenderingOnDevice() {
        // The javascript:/data:/vbscript: guard lives in the shared page
        // template, so tests/fixtures.rs pins it against a freshly built core.
        // Asserting it here as well would only add a second failure whenever
        // the bundled libmdr.so lags behind src/core/page.rs, which says
        // nothing about Android. What matters on this side is that the
        // document's links come through the bridge intact.
        val html = render("links.md")
        assertTrue("reference-style link lost", html.contains("https://example.com/reference"))
        assertTrue("mailto lost", html.contains("mailto:someone@example.com"))
        assertTrue("relative document link lost", html.contains("markdown.md"))
    }

    @Test
    fun aLargeDocumentSurvivesTheJniBoundaryIntact() {
        // markdown.md is the widest spread of constructs; check the far end of
        // it arrives, not just the opening.
        val html = render("markdown.md")
        assertTrue("the tail of the document is missing", html.contains("The end."))
        assertTrue("table did not render", html.contains("<table>"))
        assertTrue("footnotes did not render", html.contains("footnotes"))
    }
}
