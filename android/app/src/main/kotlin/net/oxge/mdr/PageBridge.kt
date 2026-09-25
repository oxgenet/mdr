package net.oxge.mdr

import android.util.Log
import android.webkit.JavascriptInterface
import org.json.JSONObject

/**
 * The `window.ipc` channel the rendered page already speaks.
 *
 * `core::page` emits an editor pane, a live-preview debounce and a Save entry
 * in its `⋮` menu, all of which call `window.ipc.postMessage(JSON)`. The
 * desktop backend implements that channel through wry; until now Android did
 * not, so those controls were visible but inert. Implementing the same three
 * commands reuses the editor the core already ships instead of building a
 * second one in Kotlin.
 *
 * Every method here is called on a WebView worker thread, never the main
 * thread, so each hands straight back to [onCommand] for the Activity to
 * marshal.
 */
class PageBridge(private val onCommand: (cmd: String, text: String) -> Unit) {

    @JavascriptInterface
    fun postMessage(json: String) {
        val message = runCatching { JSONObject(json) }.getOrElse {
            Log.w(TAG, "unparseable ipc message: $json")
            return
        }
        val cmd = message.optString("cmd")
        if (cmd.isEmpty()) return
        onCommand(cmd, message.optString("text"))
    }

    companion object {
        const val NAME = "ipc"
        private const val TAG = "mdr"

        /** A Kotlin string as a JavaScript string literal, for callbacks. */
        fun jsString(value: String): String =
            JSONObject.quote(value)

        /**
         * Tell the page a save finished. `null` means success; the page shows
         * the message otherwise. Mirrors what the desktop backend evaluates.
         */
        fun savedCallback(error: String?): String =
            "if (window.__mdrSaved) __mdrSaved(${error?.let(::jsString) ?: "null"});"

        /** Replace the editor pane's text after the document changed on disk. */
        fun setEditorCallback(text: String): String =
            "if (window.__mdrSetEditor) __mdrSetEditor(${jsString(text)});"
    }
}
