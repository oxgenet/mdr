import Foundation

/// Swift wrapper over the Rust rendering core (libmdr.a, see ../mdr_core.h).
enum MdrCore {
    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p = p else { return "" }
        defer { mdr_free(p) }
        return String(cString: p)
    }

    static var version: String { take(mdr_version()) }

    /// Full HTML page for a document. `lang` is an explicit tag or "" for auto.
    static func renderPage(markdown: String, baseDir: String, lang: String = "") -> String {
        take(mdr_render_page(markdown, baseDir, lang, false, false))
    }

    /// JavaScript that updates an already loaded page from new markdown.
    static func updateScript(markdown: String, baseDir: String, lang: String = "") -> String {
        take(mdr_render_update_js(markdown, baseDir, lang))
    }

    static func detectLang(markdown: String, lang: String = "") -> String {
        take(mdr_detect_lang(markdown, lang))
    }
}
