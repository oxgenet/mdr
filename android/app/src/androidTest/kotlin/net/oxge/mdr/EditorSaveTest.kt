package net.oxge.mdr

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Writing an edited document back, and the `window.ipc` channel the page's own
 * editor speaks over.
 *
 * The editor UI itself comes from `core::page` and is shared with the desktop,
 * so what needs proving here is the Android half: that a save reaches the
 * document, that it truncates rather than leaving a longer previous version's
 * tail behind, and that the bridge survives whatever the page sends it.
 */
@RunWith(AndroidJUnit4::class)
class EditorSaveTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val resolver get() = context.contentResolver

    private fun tempDoc(contents: String): File =
        File(context.cacheDir, "edit-${System.nanoTime()}.md").apply { writeText(contents) }

    // --- saving ---

    @Test
    fun savingReplacesTheDocumentContents() {
        val file = tempDoc("# before\n")
        try {
            val error = MarkdownDocument.save(resolver, Uri.fromFile(file), "# after\n")
            assertNull("save reported: $error", error)
            assertEquals("# after\n", file.readText())
        } finally {
            file.delete()
        }
    }

    @Test
    fun savingShorterTextTruncatesTheFile() {
        // Opened without "wt" the write would overwrite only the first bytes
        // and leave the tail of the longer previous version behind, which is
        // the kind of corruption nobody notices until the file is reopened.
        val file = tempDoc("# a very long original document that goes on for a while\n")
        try {
            assertNull(MarkdownDocument.save(resolver, Uri.fromFile(file), "# short\n"))
            assertEquals("# short\n", file.readText())
        } finally {
            file.delete()
        }
    }

    @Test
    fun savingRoundTripsUtf8() {
        val file = tempDoc("x")
        try {
            val text = "# 見出し\n\n絵文字 ☕ と記号 — あり\n"
            assertNull(MarkdownDocument.save(resolver, Uri.fromFile(file), text))
            assertEquals(text, file.readText(Charsets.UTF_8))
        } finally {
            file.delete()
        }
    }

    @Test
    fun savingToAnUnwritableLocationReportsWhy() {
        // A document opened read-only, or a provider that has revoked the
        // grant. The page shows this string, so it must not be empty.
        val error = MarkdownDocument.save(resolver, Uri.fromFile(File("/no/such/dir/x.md")), "text")
        assertNotNull("an unwritable target must report an error", error)
        assertTrue("error message was blank", error!!.isNotBlank())
    }

    @Test
    fun aDocumentReadFromDiskRemembersWhereItCameFrom() {
        // Without the uri there is nothing to save back to.
        val file = tempDoc("# hello\n")
        try {
            val doc = MarkdownDocument.from(resolver, Uri.fromFile(file))
            assertNotNull(doc)
            assertEquals(Uri.fromFile(file), doc!!.uri)
            assertEquals("# hello\n", doc.text)
        } finally {
            file.delete()
        }
    }

    @Test
    fun sharedTextHasNothingToSaveTo() {
        assertNull(MarkdownDocument.fromText("shared.md", "# x").uri)
    }

    // --- the ipc bridge ---

    @Test
    fun theBridgeForwardsCommandsFromThePage() {
        var seen: Pair<String, String>? = null
        val bridge = PageBridge { cmd, text -> seen = cmd to text }
        bridge.postMessage("""{"cmd":"save","text":"# edited"}""")
        assertEquals("save" to "# edited", seen)
    }

    @Test
    fun theBridgeIgnoresRubbish() {
        // Called from page JavaScript, so it must not be able to crash the app.
        var calls = 0
        val bridge = PageBridge { _, _ -> calls++ }
        bridge.postMessage("not json at all")
        bridge.postMessage("{}")
        bridge.postMessage("""{"text":"no command"}""")
        bridge.postMessage("")
        assertEquals("rubbish should reach no handler", 0, calls)
    }

    @Test
    fun savedCallbackDistinguishesSuccessFromFailure() {
        assertTrue(PageBridge.savedCallback(null).contains("__mdrSaved(null)"))
        val failed = PageBridge.savedCallback("disk full")
        assertTrue(failed, failed.contains("\"disk full\""))
    }

    @Test
    fun callbacksEncodeTextAsAJavascriptLiteral() {
        // The page's text is interpolated into evaluateJavascript source, so a
        // quote or newline in the document would otherwise be a syntax error.
        val js = PageBridge.setEditorCallback("say \"hi\"\nsecond line")
        assertTrue(js, js.contains("\\\"hi\\\""))
        assertTrue("newline leaked into JS source: $js", !js.contains('\n'))
    }
}
