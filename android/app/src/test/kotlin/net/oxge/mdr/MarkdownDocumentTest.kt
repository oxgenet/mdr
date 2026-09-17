package net.oxge.mdr

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * JVM unit tests — no device, no `libmdr.so`.
 *
 * Only pure Kotlin logic can live here. Everything that touches the Rust core
 * runs in `androidTest` instead, because the native library needs a real
 * Android runtime to load.
 */
class MarkdownDocumentTest {

    @Test
    fun fileUriYieldsItsContainingDirectory() {
        assertEquals("/sdcard/Documents", MarkdownDocument.baseDirForUri("file:///sdcard/Documents/notes.md"))
    }

    @Test
    fun percentEncodingInAFileUriIsDecoded() {
        assertEquals("/sdcard/My Docs", MarkdownDocument.baseDirForUri("file:///sdcard/My%20Docs/notes.md"))
    }

    @Test
    fun queryAndFragmentAreIgnored() {
        assertEquals("/a/b", MarkdownDocument.baseDirForUri("file:///a/b/c.md?x=1#top"))
    }

    @Test
    fun contentUrisHaveNoBaseDirectory() {
        // A SAF document id is not a filesystem path. Guessing one would point
        // the Rust core's image resolution at an arbitrary directory, so the
        // honest answer is "none" — see MarkdownDocument.baseDirForUri.
        assertEquals("", MarkdownDocument.baseDirForUri("content://com.android.providers.downloads/document/42"))
        assertEquals("", MarkdownDocument.baseDirForUri("content://media/external/file/99"))
    }

    @Test
    fun degenerateInputsDoNotThrow() {
        assertEquals("", MarkdownDocument.baseDirForUri(""))
        assertEquals("", MarkdownDocument.baseDirForUri("file://"))
        assertEquals("", MarkdownDocument.baseDirForUri("file:///notes.md"))
        assertEquals("", MarkdownDocument.baseDirForUri("not a uri at all"))
    }

    @Test
    fun sharedTextHasNoBaseDirectory() {
        val doc = MarkdownDocument.fromText("shared.md", "# hello")
        assertEquals("", doc.baseDir)
        assertEquals("# hello", doc.text)
        assertEquals("shared.md", doc.name)
    }
}
