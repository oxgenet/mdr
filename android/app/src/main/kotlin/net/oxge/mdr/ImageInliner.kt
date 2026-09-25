package net.oxge.mdr

/**
 * Replaces relative image references with `data:` URIs before the document
 * reaches the Rust core.
 *
 * The core resolves images from filesystem paths, which a `content://`
 * document does not have — Android hands out an opaque provider handle, not a
 * directory. When the document was opened from a folder the user granted
 * access to, the siblings can be fetched through that grant instead, inlined
 * here, and passed through untouched by the core (which leaves `data:` URIs
 * alone).
 *
 * The rewriting is deliberately separate from the Android lookup so it can be
 * tested without a device: [inline] takes a resolver function.
 */
object ImageInliner {

    /** `![alt](path)`, optionally followed by a "title". */
    private val MARKDOWN_IMAGE = Regex("""!\[([^\]]*)]\(\s*([^)\s]+)((?:\s+"[^"]*")?)\s*\)""")

    /** `<img ... src="path" ...>`, which the core passes through as raw HTML. */
    private val HTML_IMAGE = Regex("""(<img\s[^>]*?src=")([^"]+)("[^>]*>)""", RegexOption.IGNORE_CASE)

    /**
     * True when [src] names a file alongside the document rather than
     * something already self-contained or fetched over the network.
     */
    fun isRelative(src: String): Boolean {
        val s = src.trim()
        if (s.isEmpty()) return false
        // Already inlined, remote, or an absolute path/URI of some kind.
        if (s.startsWith("data:", true) || s.startsWith("//")) return false
        if (s.startsWith("/")) return false
        if (Regex("""^[a-z][a-z0-9+.\-]*:""", RegexOption.IGNORE_CASE).containsMatchIn(s)) return false
        return true
    }

    /**
     * Rewrite every relative image in [markdown] using [resolve], which returns
     * a `data:` URI for a path it can find, or null to leave it alone.
     *
     * An unresolvable image keeps its original text, so a document with one
     * missing file still renders the rest.
     */
    fun inline(markdown: String, resolve: (String) -> String?): String {
        val afterMarkdown = MARKDOWN_IMAGE.replace(markdown) { m ->
            val (alt, src, title) = m.destructured
            val replacement = if (isRelative(src)) resolve(decode(src)) else null
            if (replacement == null) m.value else "![$alt]($replacement$title)"
        }
        return HTML_IMAGE.replace(afterMarkdown) { m ->
            val (head, src, tail) = m.destructured
            val replacement = if (isRelative(src)) resolve(decode(src)) else null
            if (replacement == null) m.value else "$head$replacement$tail"
        }
    }

    /**
     * Percent-decode a path, because a Markdown link encodes spaces as `%20`
     * while the file on disk is named with a real space.
     */
    fun decode(path: String): String {
        if ('%' !in path) return path
        val out = StringBuilder(path.length)
        var i = 0
        while (i < path.length) {
            val hex = if (path[i] == '%' && i + 2 < path.length) path.substring(i + 1, i + 3) else null
            val byte = hex?.toIntOrNull(16)
            if (byte != null) {
                out.append(byte.toChar())
                i += 3
            } else {
                out.append(path[i])
                i++
            }
        }
        return out.toString()
    }

    /** Media type for a data URI, from the file extension. */
    fun mimeFor(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "bmp" -> "image/bmp"
        "svg" -> "image/svg+xml"
        else -> "application/octet-stream"
    }

    /**
     * Whether [bytes] actually look like the image [name] claims to be.
     *
     * Mirrors `core::image_validation`: a file with the wrong contents for its
     * extension is not inlined, so a mislabelled file cannot be fed to the
     * WebView as an image type it is not.
     */
    fun looksLikeImage(name: String, bytes: ByteArray): Boolean {
        fun starts(vararg prefix: Int) =
            bytes.size >= prefix.size && prefix.withIndex().all { (i, b) -> bytes[i] == b.toByte() }
        return when (name.substringAfterLast('.', "").lowercase()) {
            "png" -> starts(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            "jpg", "jpeg" -> starts(0xFF, 0xD8, 0xFF)
            "gif" -> starts(0x47, 0x49, 0x46)
            "bmp" -> starts(0x42, 0x4D)
            "webp" -> bytes.size >= 12 &&
                String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP"
            // An SVG is text; anything starting a tag or a declaration passes.
            "svg" -> String(bytes, 0, minOf(bytes.size, 64), Charsets.UTF_8).trimStart().startsWith("<")
            else -> false
        }
    }

    /** Largest image inlined, to keep a big photo from exhausting memory. */
    const val MAX_IMAGE_BYTES = 12 * 1024 * 1024
}
