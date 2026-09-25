package net.oxge.mdr

import android.content.Context
import android.content.SharedPreferences

/**
 * Reader preferences, mirroring the desktop `~/.config/mdr/config.kdl` keys.
 *
 * Only the options the rendering core can actually act on from a shell are
 * here. `remote-images` and `allow-local-http` are deliberately absent: they
 * are process-global switches in Rust that the CLI sets, and the C ABI/JNI
 * bridge exposes no setter for them yet, so a toggle would do nothing. Adding
 * one means a new FFI entry point on both platforms.
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

    companion object {
        private const val KEY_TOC = "show_toc"
        private const val KEY_LANG = "lang"

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
