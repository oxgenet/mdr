package net.oxge.mdr

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The Android half of the mobile contract.
 *
 * These assertions deliberately mirror the unit tests in `src/ffi.rs`: the same
 * rendering core, reached through JNI instead of the C ABI. The Rust tests
 * prove the core is right; these prove the bridge carries it faithfully —
 * `libmdr.so` loads, strings survive the JVM boundary in both directions,
 * booleans do not get swapped, and file paths behave on a real Android
 * filesystem rather than a desktop one.
 *
 * Anything asserted here must hold on iOS too. If you change one side, change
 * both — `docs/mobile-test-handoff.md` explains the pairing.
 */
@RunWith(AndroidJUnit4::class)
class MdrCoreInstrumentedTest {

    private val cacheDir: File
        get() = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir

    /** Eight-byte PNG signature — all the magic-byte validation looks at. */
    private val pngBytes =
        byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 0x0D, 0x0A, 0x1A, 0x0A)

    // --- the bridge itself ---

    @Test
    fun nativeLibraryLoadsAndReportsItsVersion() {
        // A stale or missing .so is the most likely Android-specific failure,
        // and it would otherwise surface as a blank page at runtime. Check the
        // load itself first: without this, every other test in the class fails
        // on an assertion that says nothing about the real cause.
        assertEquals(
            "libmdr.so did not load - build it into app/src/main/jniLibs " +
                "(see docs/mobile-test-handoff.md Task A)",
            null,
            MdrCore.loadError,
        )
        val version = MdrCore.version
        assertTrue("core reported no version", version.isNotEmpty())
        assertTrue(
            "version '$version' is not a semver-shaped string",
            Regex("""^\d+\.\d+\.\d+""").containsMatchIn(version),
        )
        assertEquals(
            "libmdr.so is a different version from the app — rebuild the Rust core",
            BuildConfig.VERSION_NAME,
            version,
        )
    }

    @Test
    fun emptyInputProducesAPageRatherThanACrash() {
        val html = MdrCore.renderPage("", "")
        assertTrue(html.contains("<html"))
        assertTrue(html.contains("</html>"))
    }

    @Test
    fun aLargeDocumentSurvivesTheJniBoundary() {
        // JNI string conversion is the size-sensitive part; a 200k-character
        // document is a realistic worst case for an LLM transcript.
        val markdown = buildString {
            repeat(4000) { append("## Heading $it\n\nSome body text for section $it.\n\n") }
        }
        val html = MdrCore.renderPage(markdown, "")
        assertTrue(html.contains("Heading 3999"))
        assertTrue(html.contains("</html>"))
    }

    // --- view options ---

    @Test
    fun viewFlagsReachTheRenderedPage() {
        // editor/toc cross as JNI booleans; swapping them would open the wrong
        // mode with no other visible symptom.
        assertTrue(MdrCore.renderPage("# t", "", editor = false, toc = false).contains("""<body class="no-toc">"""))
        assertTrue(MdrCore.renderPage("# t", "", editor = true, toc = false).contains("""<body class="no-toc editing">"""))
        assertTrue(MdrCore.renderPage("# t", "", editor = false, toc = true).contains("""<body class="">"""))
        assertTrue(MdrCore.renderPage("# t", "", editor = true, toc = true).contains("""<body class="editing">"""))
    }

    @Test
    fun documentSourceIsEscapedIntoTheEditorPane() {
        val html = MdrCore.renderPage("<b>bold</b> & <i>x</i>", "", editor = true)
        assertTrue("source not escaped into <textarea>", html.contains("&lt;b&gt;bold&lt;/b&gt; &amp; &lt;i&gt;x&lt;/i&gt;"))
        assertTrue("raw HTML should still render in the body", html.contains("<b>bold</b>"))
    }

    @Test
    fun headingsBecomeTocEntriesTheMenuCanScrape() {
        // MainActivity.showToc() reads exactly these elements.
        val html = MdrCore.renderPage("# Getting Started\n\n## Install", "", toc = true)
        assertTrue(html.contains("""<li class="toc-h1"><a href="#getting-started">Getting Started</a></li>"""))
        assertTrue(html.contains("""<li class="toc-h2"><a href="#install">Install</a></li>"""))
        assertTrue(html.contains("""<h1 id="getting-started">"""))
    }

    // --- language resolution (same order as the Rust core) ---

    @Test
    fun languageIsDetectedFromContent() {
        assertEquals("ja", MdrCore.detectLang("これは日本語の文書です。"))
        assertEquals("ko", MdrCore.detectLang("이것은 한국어 문서입니다."))
        assertEquals("zh-Hans", MdrCore.detectLang("这是简体中文的文档。"))
    }

    @Test
    fun frontMatterBeatsExplicitLangWhichBeatsDetection() {
        val ko = "이것은 한국어 문서입니다."
        assertEquals("ja", MdrCore.detectLang(ko, "ja"))
        assertEquals("zh-Hant", MdrCore.detectLang("---\nlang: zh-Hant\n---\n$ko", "ja"))
        assertTrue(MdrCore.renderPage(ko, "", lang = "ja").contains("""<html lang="ja">"""))
    }

    @Test
    fun autoMeansNoExplicitLanguage() {
        assertEquals("ja", MdrCore.detectLang("これは日本語です。", "auto"))
    }

    @Test
    fun anUnparseableLanguageTagFallsBackToDetection() {
        assertEquals("ja", MdrCore.detectLang("これは日本語です。", "xx-YY"))
    }

    // --- live update script ---

    @Test
    fun updateScriptJsonEncodesTheDocument() {
        // WebView.evaluateJavascript takes source, not arguments: a raw quote,
        // backslash or newline from the document would be a syntax error.
        val js = MdrCore.updateScript("He said \"hi\"\n\nC:\\path\\to", "")
        assertFalse("update script must stay on one line: $js", js.contains('\n'))
        assertTrue("quotes not escaped: $js", js.contains("""\"hi\""""))
        assertTrue("backslashes not escaped: $js", js.contains("""C:\\path\\to"""))
    }

    @Test
    fun updateScriptTracksTheLanguage() {
        val js = MdrCore.updateScript("---\nlang: zh-Hant\n---\n\nplain text", "")
        assertTrue(js.contains("""setAttribute('lang', "zh-Hant")"""))
    }

    // --- base_dir behaviour on a real Android filesystem ---

    @Test
    fun relativeImagesAreEmbeddedFromBaseDir() {
        // The page is loaded with a null base URL, so nothing can be fetched
        // from disk afterwards — images have to be inlined at render time.
        val dir = File(cacheDir, "img-${System.nanoTime()}").apply { mkdirs() }
        try {
            File(dir, "pic.png").writeBytes(pngBytes)
            val html = MdrCore.renderPage("![a](pic.png)", dir.absolutePath)
            assertTrue("image was not inlined", html.contains("data:image/png;base64,"))
            assertFalse(html.contains("""src="pic.png""""))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun imagesOutsideBaseDirAreNotEmbedded() {
        val root = File(cacheDir, "esc-${System.nanoTime()}").apply { mkdirs() }
        try {
            val sub = File(root, "sub").apply { mkdirs() }
            File(root, "secret.png").writeBytes(pngBytes)
            val html = MdrCore.renderPage("![a](../secret.png)", sub.absolutePath)
            assertFalse("image escaped base_dir", html.contains("data:image/png;base64,"))
            assertTrue(html.contains("""src="../secret.png""""))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun anEmptyBaseDirStillRenders() {
        // What a `content://` document gives us: no directory at all.
        val html = MdrCore.renderPage("# t\n\n![a](pic.png)", "")
        assertTrue(html.contains("</html>"))
        assertTrue(html.contains("""src="pic.png""""))
    }
}
