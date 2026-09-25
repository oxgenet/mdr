import Foundation

/// Swift wrapper over the Rust rendering core (libmdr.a, see ../mdr_core.h).
enum MdrCore {
    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p = p else { return "" }
        defer { mdr_free(p) }
        return String(cString: p)
    }

    static var version: String { take(mdr_version()) }

    /// Full HTML page for a document, viewer/editor chrome included.
    ///
    /// `lang` is an explicit BCP 47 tag or "" to detect from the content.
    /// `editor` and `toc` mirror `MdrCore.renderPage` on Android; the app only
    /// ever renders in viewer mode (its own native chrome replaces the page's),
    /// but the contract tests drive all four combinations.
    static func renderPage(
        markdown: String,
        baseDir: String,
        lang: String = "",
        editor: Bool = false,
        toc: Bool = false
    ) -> String {
        take(mdr_render_page(markdown, baseDir, lang, editor, toc))
    }

    /// JavaScript that updates an already loaded page from new markdown.
    static func updateScript(markdown: String, baseDir: String, lang: String = "") -> String {
        take(mdr_render_update_js(markdown, baseDir, lang))
    }

    // MARK: - Image URL policy
    //
    // These are process-global in `core::urlpolicy`, not per-render, so a
    // shell sets them once at launch rather than passing them to every call.
    // The desktop drives the same switches from --no-remote-images and
    // config.kdl.

    /// Fetch images a document links over the network at all.
    static var remoteImages: Bool {
        get { mdr_remote_images() }
        set { mdr_set_remote_images(newValue) }
    }

    /// Permit plain http for localhost, private addresses and *.local.
    /// A narrowing of ``remoteImages``: it has no effect while that is off.
    static var allowLocalHttp: Bool {
        get { mdr_allow_local_http() }
        set { mdr_set_allow_local_http(newValue) }
    }

    static func detectLang(markdown: String, lang: String = "") -> String {
        take(mdr_detect_lang(markdown, lang))
    }
}
