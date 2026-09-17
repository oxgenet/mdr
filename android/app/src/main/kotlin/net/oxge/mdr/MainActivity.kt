package net.oxge.mdr

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.webkit.WebView
import android.widget.SearchView
import android.widget.Toast
import org.json.JSONArray

/**
 * The reader. One document at a time in a WebView, rendered by the Rust core.
 *
 * The page that [MdrCore] produces already carries the table of contents, the
 * search machinery and the styling; this Activity drives them from native UI
 * instead of the page's own `⋮` menu, the way `DocumentViewController` does on
 * iOS. Keeping the page identical across platforms is the point — a rendering
 * bug reproduces everywhere, and is fixed once.
 */
class MainActivity : Activity() {

    private lateinit var webView: WebView
    private var document: MarkdownDocument? = null

    private val openDocument =
        object {
            fun launch() {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/markdown", "text/x-markdown", "text/plain"))
                }
                startActivityForResult(intent, REQUEST_OPEN)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this).apply {
            settings.javaScriptEnabled = true       // the page's TOC + search are JS
            settings.allowFileAccess = false        // images are inlined; nothing to read from disk
            settings.allowContentAccess = false
        }
        setContentView(webView)
        handleIntent(intent)
        if (document == null) showWelcome()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    /** Open whatever a VIEW / SEND intent carried, if anything. */
    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data?.let { load(it) }
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                when {
                    uri != null -> load(uri)
                    text != null -> show(MarkdownDocument.fromText("shared.md", text))
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_OPEN && resultCode == RESULT_OK) {
            data?.data?.let { load(it) }
        }
    }

    private fun load(uri: Uri) {
        val doc = MarkdownDocument.from(contentResolver, uri)
        if (doc == null) {
            Toast.makeText(this, R.string.open_failed, Toast.LENGTH_LONG).show()
            return
        }
        show(doc)
    }

    /**
     * Render [doc] and display it.
     *
     * `baseUrl` is null, matching `WKWebView.loadHTMLString(_:baseURL: nil)` on
     * iOS: the page must be self-contained, and the Rust core has already
     * inlined every local image as a data URI.
     */
    private fun show(doc: MarkdownDocument) {
        document = doc
        title = doc.name
        val html = MdrCore.renderPage(doc.text, doc.baseDir)
        if (html.isEmpty()) {
            // Only happens when libmdr.so is missing for this device's ABI.
            // Say so instead of showing a blank screen.
            webView.loadDataWithBaseURL(null, nativeMissingHtml(), "text/html", "utf-8", null)
            return
        }
        webView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
    }

    private fun nativeMissingHtml(): String =
        "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>" +
            "<body style=\"font:16px system-ui;padding:24px;color:#b3261e\">" +
            "<h2>Rendering core unavailable</h2><p>" +
            android.text.Html.escapeHtml(MdrCore.loadError ?: "unknown error") +
            "</p></body>"

    private fun showWelcome() {
        show(MarkdownDocument.fromText(getString(R.string.app_name), WELCOME_MD))
    }

    // MARK: menu

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, ID_OPEN, 0, R.string.action_open)
            .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)

        val search = menu.add(0, ID_SEARCH, 1, R.string.action_search)
        search.setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM or MenuItem.SHOW_AS_ACTION_COLLAPSE_ACTION_VIEW)
        search.actionView = SearchView(this).apply {
            queryHint = getString(R.string.search_hint)
            setOnQueryTextListener(object : SearchView.OnQueryTextListener {
                override fun onQueryTextSubmit(query: String?): Boolean {
                    webView.evaluateJavascript("window.searchNav && searchNav(1)", null)
                    return true
                }

                override fun onQueryTextChange(newText: String?): Boolean {
                    search(newText.orEmpty())
                    return true
                }
            })
        }

        menu.add(0, ID_TOC, 2, R.string.action_toc)
            .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
        menu.add(0, ID_SHARE, 3, R.string.action_share)
            .setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        ID_OPEN -> { openDocument.launch(); true }
        ID_TOC -> { showToc(); true }
        ID_SHARE -> { shareText(); true }
        else -> super.onOptionsItemSelected(item)
    }

    /** Drive the page's own highlighter — the same `mdrSearch` hook iOS uses. */
    private fun search(query: String) {
        webView.evaluateJavascript("window.mdrSearch ? mdrSearch(${jsString(query)}) : 0", null)
    }

    /**
     * Scrape the page's table of contents and offer it as a native list.
     *
     * The sidebar is hidden on a phone, but it is still in the DOM, so the
     * headings and their anchor ids come from the same place the desktop
     * sidebar uses — no second TOC implementation to keep in step.
     */
    private fun showToc() {
        val js = "JSON.stringify(Array.from(document.querySelectorAll('.sidebar li')).map(function(li){" +
            "return {t: li.textContent, h: li.querySelector('a').getAttribute('href')};}))"
        webView.evaluateJavascript(js) { raw ->
            val entries = parseToc(raw)
            if (entries.isEmpty()) {
                Toast.makeText(this, R.string.no_headings, Toast.LENGTH_SHORT).show()
                return@evaluateJavascript
            }
            AlertDialog.Builder(this)
                .setTitle(R.string.action_toc)
                .setItems(entries.map { it.first }.toTypedArray()) { _, which ->
                    val anchor = entries[which].second.removePrefix("#")
                    webView.evaluateJavascript(
                        "document.getElementById(${jsString(anchor)})" +
                            "?.scrollIntoView({behavior:'smooth',block:'start'})",
                        null,
                    )
                }
                .show()
        }
    }

    private fun shareText() {
        val doc = document ?: return
        startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/markdown"
                    putExtra(Intent.EXTRA_TITLE, doc.name)
                    putExtra(Intent.EXTRA_TEXT, doc.text)
                },
                getString(R.string.action_share),
            ),
        )
    }

    companion object {
        private const val REQUEST_OPEN = 1
        private const val ID_OPEN = 1
        private const val ID_SEARCH = 2
        private const val ID_TOC = 3
        private const val ID_SHARE = 4

        private val WELCOME_MD = """
            # mdr

            Open a Markdown file to start reading — **Open** in the menu, or pick
            mdr when another app offers to open a `.md`.

            Mermaid diagrams, tables, task lists, footnotes and CJK text all
            render the same here as on the desktop: one Rust core does the work.
        """.trimIndent()

        /**
         * A Kotlin string as a JavaScript string literal.
         *
         * `evaluateJavascript` takes source, not arguments, so anything
         * interpolated into it has to be encoded. `JSONArray` does exactly the
         * escaping a JS string literal needs, and is in the platform already.
         */
        fun jsString(value: String): String =
            JSONArray().put(value).toString().let { it.substring(1, it.length - 1) }

        /** Parse the JSON `evaluateJavascript` hands back for the TOC scrape. */
        fun parseToc(raw: String?): List<Pair<String, String>> {
            if (raw.isNullOrBlank() || raw == "null") return emptyList()
            // The result arrives as a JSON *string* containing JSON.
            val inner = runCatching { JSONArray("[$raw]").getString(0) }.getOrNull() ?: return emptyList()
            val array = runCatching { JSONArray(inner) }.getOrNull() ?: return emptyList()
            return (0 until array.length()).mapNotNull { i ->
                val o = array.optJSONObject(i) ?: return@mapNotNull null
                val text = o.optString("t").trim()
                val href = o.optString("h")
                if (text.isEmpty() || href.isEmpty()) null else text to href
            }
        }
    }
}
