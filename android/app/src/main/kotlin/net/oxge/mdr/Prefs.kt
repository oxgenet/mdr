package net.oxge.mdr

import android.content.Context
import android.content.SharedPreferences

/**
 * Reader preferences, mirroring the desktop `~/.config/mdr/config.kdl` keys.
 *
 * Only options the rendering core can actually act on from a shell are here.
 * `remoteImages` and `allowLocalHttp` are process-global in Rust rather than
 * per-render, so [applyImagePolicy] pushes them across the bridge instead of
 * passing them with the document.
 */
class Prefs(private val sp: SharedPreferences) {

    /** Show the table-of-contents sidebar when a document opens. */
    var showToc: Boolean
        get() = sp.getBoolean(KEY_TOC, false)
        set(v) = sp.edit().putBoolean(KEY_TOC, v).apply()

    /**
     * Explicit BCP 47 tag for CJK rendering, or "" to detect from content.
     * A document's own front-matter `lang:` still wins over this, exactly as
     * on the desktop.
     */
    var lang: String
        get() = sp.getString(KEY_LANG, "") ?: ""
        set(v) = sp.edit().putString(KEY_LANG, v).apply()

    /** Load images a document links by http(s) URL. Default: on, as on desktop. */
    var remoteImages: Boolean
        get() = sp.getBoolean(KEY_REMOTE_IMAGES, true)
        set(v) = sp.edit().putBoolean(KEY_REMOTE_IMAGES, v).apply()

    /**
     * Allow plain http for localhost, private IP literals and `*.local` — a
     * NAS or a dev server on your own network. No effect while
     * [remoteImages] is off.
     */
    var allowLocalHttp: Boolean
        get() = sp.getBoolean(KEY_LOCAL_HTTP, true)
        set(v) = sp.edit().putBoolean(KEY_LOCAL_HTTP, v).apply()

    /** Push both into the core, which holds them process-wide. */
    fun applyImagePolicy() {
        MdrCore.setRemoteImages(remoteImages)
        MdrCore.setAllowLocalHttp(allowLocalHttp)
    }

    companion object {
        private const val KEY_TOC = "show_toc"
        private const val KEY_LANG = "lang"
        private const val KEY_REMOTE_IMAGES = "remote_images"
        private const val KEY_LOCAL_HTTP = "allow_local_http"

        /** Tags offered in the picker, in the order they are shown. */
        val LANG_TAGS = listOf("", "ja", "zh-Hans", "zh-Hant", "ko")

        fun from(context: Context): Prefs =
            Prefs(context.getSharedPreferences("mdr", Context.MODE_PRIVATE))

        /**
         * Index of [tag] in [LANG_TAGS], falling back to 0 ("auto").
         *
         * A tag can go stale — it is persisted across upgrades and could name a
         * language a later build no longer offers — so an unknown value has to
         * degrade to auto rather than crash the settings screen.
         */
        fun langIndex(tag: String): Int = LANG_TAGS.indexOf(tag).takeIf { it >= 0 } ?: 0
    }
}
