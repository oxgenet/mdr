package net.oxge.mdr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rewriting half of relative-image support, which is pure Kotlin and so
 * runs without a device. The `DocumentsContract` lookup it delegates to is
 * covered in `androidTest`.
 */
class ImageInlinerTest {

    private val stub: (String) -> String? = { "data:image/png;base64,AAAA" }

    // --- what counts as relative ---

    @Test
    fun siblingFilesAreRelative() {
        assertTrue(ImageInliner.isRelative("pic.png"))
        assertTrue(ImageInliner.isRelative("images/pic.png"))
        assertTrue(ImageInliner.isRelative("./pic.png"))
    }

    @Test
    fun alreadyResolvedSourcesAreLeftAlone() {
        // Inlining these would either double-encode or try to fetch the network
        // through a provider that cannot.
        assertFalse(ImageInliner.isRelative("data:image/png;base64,AAAA"))
        assertFalse(ImageInliner.isRelative("https://example.com/a.png"))
        assertFalse(ImageInliner.isRelative("http://example.com/a.png"))
        assertFalse(ImageInliner.isRelative("content://provider/1"))
        assertFalse(ImageInliner.isRelative("file:///sdcard/a.png"))
        assertFalse(ImageInliner.isRelative("//cdn.example.com/a.png"))
        assertFalse(ImageInliner.isRelative("/absolute/a.png"))
        assertFalse(ImageInliner.isRelative(""))
    }

    // --- rewriting ---

    @Test
    fun markdownImagesAreRewritten() {
        val out = ImageInliner.inline("![a cat](cat.png)", stub)
        assertEquals("![a cat](data:image/png;base64,AAAA)", out)
    }

    @Test
    fun aTitleIsPreserved() {
        val out = ImageInliner.inline("""![a](cat.png "Tiddles")""", stub)
        assertEquals("""![a](data:image/png;base64,AAAA "Tiddles")""", out)
    }

    @Test
    fun rawHtmlImagesAreRewritten() {
        // comrak runs with render.unsafe = true, so documents really do use
        // <img> for sizing.
        val out = ImageInliner.inline("""<img src="cat.png" width="300"/>""", stub)
        assertEquals("""<img src="data:image/png;base64,AAAA" width="300"/>""", out)
    }

    @Test
    fun unresolvableImagesKeepTheirOriginalText() {
        // One missing file must not stop the rest of the document rendering.
        val md = "![a](missing.png) and ![b](found.png)"
        val out = ImageInliner.inline(md) { if (it == "found.png") "data:image/png;base64,AAAA" else null }
        assertEquals("![a](missing.png) and ![b](data:image/png;base64,AAAA)", out)
    }

    @Test
    fun remoteAndInlineImagesAreUntouched() {
        val md = "![a](https://example.com/a.png) ![b](data:image/png;base64,ZZZZ)"
        assertEquals(md, ImageInliner.inline(md, stub))
    }

    @Test
    fun linksAreNotMistakenForImages() {
        // `[text](x.png)` is a link, not an image - no leading bang.
        val md = "[not an image](cat.png)"
        assertEquals(md, ImageInliner.inline(md, stub))
    }

    @Test
    fun severalImagesInOneDocumentAreAllRewritten() {
        val md = "![a](1.png)\n\ntext\n\n![b](2.png)\n\n<img src=\"3.png\">"
        val out = ImageInliner.inline(md) { "data:image/png;base64,$it" }
        assertTrue(out, out.contains("data:image/png;base64,1.png"))
        assertTrue(out, out.contains("data:image/png;base64,2.png"))
        assertTrue(out, out.contains("data:image/png;base64,3.png"))
    }

    @Test
    fun percentEncodedPathsAreDecodedBeforeLookup() {
        // The document writes %20; the file is named with a real space.
        var asked: String? = null
        ImageInliner.inline("![a](my%20pic.png)") { asked = it; null }
        assertEquals("my pic.png", asked)
    }

    // --- media types and validation ---

    @Test
    fun mimeTypesComeFromTheExtension() {
        assertEquals("image/png", ImageInliner.mimeFor("a.png"))
        assertEquals("image/jpeg", ImageInliner.mimeFor("a.JPG"))
        assertEquals("image/svg+xml", ImageInliner.mimeFor("a.svg"))
        assertEquals("application/octet-stream", ImageInliner.mimeFor("a.unknown"))
    }

    @Test
    fun contentsMustMatchTheExtension() {
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        assertTrue(ImageInliner.looksLikeImage("a.png", png))
        // A file renamed to .png is not fed to the WebView as one, matching
        // core::image_validation on the desktop.
        assertFalse(ImageInliner.looksLikeImage("a.png", "<html>".toByteArray()))
        assertFalse(ImageInliner.looksLikeImage("a.jpg", png))
        assertTrue(ImageInliner.looksLikeImage("a.svg", "<svg xmlns=\"\"></svg>".toByteArray()))
        assertFalse(ImageInliner.looksLikeImage("a.svg", "not markup".toByteArray()))
    }

    @Test
    fun truncatedFilesDoNotPassValidation() {
        assertFalse(ImageInliner.looksLikeImage("a.png", byteArrayOf(0x89.toByte())))
        assertFalse(ImageInliner.looksLikeImage("a.webp", "RIFF".toByteArray()))
        assertFalse(ImageInliner.looksLikeImage("a.png", ByteArray(0)))
    }
}
