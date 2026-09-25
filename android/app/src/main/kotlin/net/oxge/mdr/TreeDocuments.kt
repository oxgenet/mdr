package net.oxge.mdr

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import android.util.Log

/**
 * Reading siblings of a document through a folder the user granted access to.
 *
 * A single-document `content://` URI cannot name its neighbours — the Storage
 * Access Framework hands out an opaque handle, not a directory. A *tree* URI
 * from `ACTION_OPEN_DOCUMENT_TREE` can, which is the only way an Android app
 * may resolve `![](pic.png)` against the folder a document lives in.
 *
 * Framework `DocumentsContract` throughout, so this needs no extra dependency.
 */
object TreeDocuments {

    private const val TAG = "mdr"

    private val PROJECTION = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
    )

    /** One entry in a granted folder. */
    data class Entry(val name: String, val uri: Uri, val mimeType: String)

    /** Markdown documents directly inside [treeUri], for the folder picker. */
    fun listMarkdown(resolver: ContentResolver, treeUri: Uri): List<Entry> =
        children(resolver, treeUri, DocumentsContract.getTreeDocumentId(treeUri))
            .filter { it.name.substringAfterLast('.', "").lowercase() in MARKDOWN_EXTENSIONS }
            .sortedBy { it.name.lowercase() }

    /**
     * Resolve a document-relative path such as `images/pic.png` inside
     * [treeUri].
     *
     * `..` is refused rather than followed: images are embedded without the
     * reader doing anything, so they stay inside the folder that was granted,
     * matching how the desktop confines them to the document's directory.
     */
    fun resolveRelative(resolver: ContentResolver, treeUri: Uri, path: String): Entry? {
        var parentId = DocumentsContract.getTreeDocumentId(treeUri)
        val segments = path.split('/').filter { it.isNotEmpty() && it != "." }
        if (segments.isEmpty() || segments.any { it == ".." }) return null
        segments.dropLast(1).forEach { dir ->
            val match = children(resolver, treeUri, parentId).firstOrNull {
                it.name == dir && it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR
            } ?: return null
            parentId = DocumentsContract.getDocumentId(match.uri)
        }
        return children(resolver, treeUri, parentId).firstOrNull { it.name == segments.last() }
    }

    /**
     * Read [entry] as a `data:` URI, or null if it is missing, too large, or
     * does not match the image type its name claims.
     */
    fun asDataUri(resolver: ContentResolver, entry: Entry): String? {
        val bytes = runCatching {
            resolver.openInputStream(entry.uri)?.use { stream ->
                // Stop one byte past the cap: enough to know the file is
                // oversized, without pulling a huge photo into memory first.
                val limit = ImageInliner.MAX_IMAGE_BYTES + 1
                val collected = java.io.ByteArrayOutputStream()
                val chunk = ByteArray(64 * 1024)
                while (collected.size() <= limit) {
                    val read = stream.read(chunk)
                    if (read < 0) break
                    collected.write(chunk, 0, read)
                }
                collected.toByteArray()
            }
        }.onFailure { Log.w(TAG, "cannot read image ${entry.name}", it) }.getOrNull() ?: return null

        if (bytes.size > ImageInliner.MAX_IMAGE_BYTES) {
            Log.w(TAG, "image ${entry.name} is larger than ${ImageInliner.MAX_IMAGE_BYTES} bytes; skipped")
            return null
        }
        if (!ImageInliner.looksLikeImage(entry.name, bytes)) {
            Log.w(TAG, "image ${entry.name} does not match its extension; skipped")
            return null
        }
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return "data:${ImageInliner.mimeFor(entry.name)};base64,$b64"
    }

    /**
     * Inline every relative image in [markdown] that can be found under
     * [treeUri]. Anything unresolvable keeps its original text.
     */
    fun inlineImages(resolver: ContentResolver, treeUri: Uri, markdown: String): String {
        val cache = HashMap<String, String?>()
        return ImageInliner.inline(markdown) { path ->
            cache.getOrPut(path) {
                resolveRelative(resolver, treeUri, path)?.let { asDataUri(resolver, it) }
            }
        }
    }

    private fun children(resolver: ContentResolver, treeUri: Uri, parentDocumentId: String): List<Entry> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        return runCatching {
            resolver.query(childrenUri, PROJECTION, null, null, null)?.use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        val id = cursor.getString(0) ?: continue
                        add(
                            Entry(
                                name = cursor.getString(1) ?: continue,
                                uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                                mimeType = cursor.getString(2).orEmpty(),
                            ),
                        )
                    }
                }
            }
        }.onFailure { Log.w(TAG, "cannot list $childrenUri", it) }.getOrNull().orEmpty()
    }

    private val MARKDOWN_EXTENSIONS = setOf("md", "markdown", "mdown", "mkd", "mdx", "txt")
}
