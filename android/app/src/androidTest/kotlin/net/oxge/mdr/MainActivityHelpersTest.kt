package net.oxge.mdr

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The two pure helpers that sit between the Activity and the WebView.
 *
 * They run on-device rather than as JVM unit tests because both use
 * `org.json`, which is a stub returning defaults in local unit tests.
 */
@RunWith(AndroidJUnit4::class)
class MainActivityHelpersTest {

    // --- jsString: interpolating user text into evaluateJavascript source ---

    @Test
    fun jsStringQuotesAndEscapesForJavascriptSource() {
        // A search query comes straight from the keyboard; unescaped, a quote
        // or backslash would be a syntax error, not a failed search.
        assertEquals("\"plain\"", MainActivity.jsString("plain"))
        assertTrue(MainActivity.jsString("""say "hi"""").contains("""\""""))
        assertTrue(MainActivity.jsString("""back\slash""").contains("""\\"""))
    }

    @Test
    fun jsStringKeepsTheResultOnOneLine() {
        val encoded = MainActivity.jsString("line one\nline two")
        assertTrue("newline leaked into JS source: $encoded", !encoded.contains('\n'))
    }

    @Test
    fun jsStringSurvivesCjkAndEmptyInput() {
        assertTrue(MainActivity.jsString("日本語").contains("日本語"))
        assertEquals("\"\"", MainActivity.jsString(""))
    }

    // --- parseToc: reading back what evaluateJavascript returned ---

    @Test
    fun parseTocReadsHeadingsAndAnchors() {
        // evaluateJavascript hands back a JSON *string* containing JSON.
        val raw = "\"[{\\\"t\\\":\\\"Intro\\\",\\\"h\\\":\\\"#intro\\\"}," +
            "{\\\"t\\\":\\\"Install\\\",\\\"h\\\":\\\"#install\\\"}]\""
        val entries = MainActivity.parseToc(raw)
        assertEquals(2, entries.size)
        assertEquals("Intro" to "#intro", entries[0])
        assertEquals("Install" to "#install", entries[1])
    }

    @Test
    fun parseTocReturnsEmptyForADocumentWithoutHeadings() {
        assertEquals(emptyList<Pair<String, String>>(), MainActivity.parseToc("\"[]\""))
    }

    @Test
    fun parseTocSurvivesNullAndMalformedResults() {
        // evaluateJavascript returns the string "null" when the script throws,
        // and the page may have been replaced mid-call.
        assertEquals(emptyList<Pair<String, String>>(), MainActivity.parseToc(null))
        assertEquals(emptyList<Pair<String, String>>(), MainActivity.parseToc("null"))
        assertEquals(emptyList<Pair<String, String>>(), MainActivity.parseToc(""))
        assertEquals(emptyList<Pair<String, String>>(), MainActivity.parseToc("not json"))
    }
}
