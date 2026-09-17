package net.oxge.mdr

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns

/**
 * One Markdown document, loaded far enough to render it.
 *
 * @param baseDir directory relative images resolve against. Often "" on
 *   Android: a `content://` URI from the Storage Access Framework names a
 *   document, not a directory, so there is nothing to resolve against. See
 *   [baseDirForUri].
 */
data class MarkdownDocument(
    val name: String,
    val text: String,
    val baseDir: String,
) {
    companion object {

        /** Read [uri] through the content resolver. Null when it cannot be read. */
        fun from(resolver: ContentResolver, uri: Uri): MarkdownDocument? {
            val text = runCatching {
                resolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            }.getOrNull() ?: return null
            return MarkdownDocument(
                name = displayName(resolver, uri),
                text = text,
                baseDir = baseDirForUri(uri.toString()),
            )
        }

        /** A document made from shared text, which has no file behind it. */
        fun fromText(name: String, text: String) = MarkdownDocument(name, text, "")

        private fun displayName(resolver: ContentResolver, uri: Uri): String {
            val fromProvider = runCatching {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null }
            }.getOrNull()
            return fromProvider ?: uri.lastPathSegment?.substringAfterLast('/') ?: "document.md"
        }

        /**
         * Directory for relative image resolution, derived from the URI string.
         *
         * Only a `file://` URI names a real directory. A `content://` URI is an
         * opaque provider handle — its path segments are not filesystem paths,
         * so anything derived from them would be a guess, and a wrong `baseDir`
         * makes the Rust core read files the user never opened. "" is the
         * honest answer: images that are not already `data:` URIs stay unloaded.
         *
         * Kept as plain string handling (no `android.net.Uri`) so the JVM unit
         * tests can exercise it without a device.
         */
        fun baseDirForUri(uri: String): String {
            if (!uri.startsWith("file://")) return ""
            val path = uri.removePrefix("file://").substringBefore('?').substringBefore('#')
            val decoded = percentDecode(path)
            val cut = decoded.lastIndexOf('/')
            return if (cut <= 0) "" else decoded.substring(0, cut)
        }

        /** Minimal percent-decoding for the path part of a `file://` URI. */
        private fun percentDecode(s: String): String {
            if ('%' !in s) return s
            val out = StringBuilder(s.length)
            var i = 0
            while (i < s.length) {
                val c = s[i]
                val hex = if (c == '%' && i + 2 < s.length) s.substring(i + 1, i + 3) else null
                val byte = hex?.toIntOrNull(16)
                if (byte != null) {
                    out.append(byte.toChar())
                    i += 3
                } else {
                    out.append(c)
                    i++
                }
            }
            return out.toString()
        }
    }
}
