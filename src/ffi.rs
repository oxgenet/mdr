//! C ABI for native shells (iOS / Android). Strings are UTF-8, NUL-terminated;
//! every `*mut c_char` returned here must be released with [`mdr_free`].

use crate::core::page::{lang_tag, render_page, render_update_js};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

unsafe fn arg(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

fn out(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

fn opt(s: &str) -> Option<&str> {
    if s.is_empty() { None } else { Some(s) }
}

/// Render a complete HTML page (viewer/editor UI included) for `markdown`.
/// `base_dir` resolves relative images; `lang` is an explicit tag or "" for auto.
///
/// # Safety
///
/// Each of `markdown`, `base_dir` and `lang` must be either null or a pointer
/// to a NUL-terminated C string that stays valid for the duration of the call.
/// Null is accepted and read as an empty string. The returned pointer is owned
/// by the caller and must be released with [`mdr_free`]; it is null if the
/// rendered page could not be converted to a C string.
#[no_mangle]
pub unsafe extern "C" fn mdr_render_page(
    markdown: *const c_char,
    base_dir: *const c_char,
    lang: *const c_char,
    editor: bool,
    toc: bool,
) -> *mut c_char {
    let md = arg(markdown);
    let base = arg(base_dir);
    let lang = arg(lang);
    out(render_page(&md, Path::new(&base), opt(&lang), editor, toc))
}

/// JS that updates an already loaded page (body, TOC, lang) from new markdown.
///
/// # Safety
///
/// Each of `markdown`, `base_dir` and `lang` must be either null or a pointer
/// to a NUL-terminated C string that stays valid for the duration of the call.
/// Null is accepted and read as an empty string. The returned pointer is owned
/// by the caller and must be released with [`mdr_free`].
#[no_mangle]
pub unsafe extern "C" fn mdr_render_update_js(
    markdown: *const c_char,
    base_dir: *const c_char,
    lang: *const c_char,
) -> *mut c_char {
    let md = arg(markdown);
    let base = arg(base_dir);
    let lang = arg(lang);
    out(render_update_js(&md, Path::new(&base), opt(&lang)))
}

/// Resolved BCP 47 language tag for the document ("" when none).
///
/// # Safety
///
/// Both `markdown` and `lang` must be either null or a pointer to a
/// NUL-terminated C string that stays valid for the duration of the call.
/// Null is accepted and read as an empty string. The returned pointer is owned
/// by the caller and must be released with [`mdr_free`].
#[no_mangle]
pub unsafe extern "C" fn mdr_detect_lang(markdown: *const c_char, lang: *const c_char) -> *mut c_char {
    let md = arg(markdown);
    let lang = arg(lang);
    out(lang_tag(&md, opt(&lang)))
}

/// Allow or forbid loading images from http(s) URLs at all.
///
/// The policy is process-global (see `core::urlpolicy`), which is why the
/// shells set it rather than passing it with every render. Desktop takes it
/// from `--no-remote-images` / `config.kdl`; the mobile shells have no config
/// file, so they call this from their settings screen.
#[no_mangle]
pub extern "C" fn mdr_set_remote_images(on: bool) {
    crate::core::urlpolicy::set_remote_images(on);
}

/// Allow or forbid plain-http images for localhost, private IP literals and
/// `*.local`. Has no effect when remote images are off altogether.
#[no_mangle]
pub extern "C" fn mdr_set_allow_local_http(on: bool) {
    crate::core::urlpolicy::set_allow_local_http(on);
}

/// Current remote-image setting, so a shell can show the real state rather
/// than assuming its own stored preference was applied.
#[no_mangle]
pub extern "C" fn mdr_remote_images() -> bool {
    crate::core::urlpolicy::remote_images()
}

/// Current plain-http-for-local-addresses setting.
#[no_mangle]
pub extern "C" fn mdr_allow_local_http() -> bool {
    crate::core::urlpolicy::allow_local_http()
}

/// Library version string.
#[no_mangle]
pub extern "C" fn mdr_version() -> *mut c_char {
    out(env!("CARGO_PKG_VERSION").to_string())
}

/// Release a string returned by this library.
///
/// # Safety
///
/// `p` must be null, or a pointer returned by one of this module's render
/// functions and not yet freed. Passing anything else — a pointer this library
/// did not produce, or one already given to `mdr_free` — is undefined
/// behaviour. Null is ignored.
#[no_mangle]
pub unsafe extern "C" fn mdr_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

/// Contract tests for the C ABI.
///
/// This is the whole surface the iOS shell (and any future Android shell) sees
/// — `MdrCore.swift` calls these five functions and nothing else — so a change
/// that only breaks a phone shows up here, on any host, without a device.
///
/// Assertions stay clear of the OS locale: an empty or Latin-only document
/// falls back to `LANG`, so only documents that carry their own script (or an
/// explicit tag) may be asserted on.
#[cfg(test)]
mod tests {
    use super::*;

    /// Eight-byte PNG signature. `core::image_validation` checks the magic
    /// bytes and the embedding path just reads the file, so this is a
    /// sufficient stand-in for a real image.
    const PNG: &[u8] = &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    unsafe fn take(p: *mut c_char) -> String {
        let s = CStr::from_ptr(p).to_string_lossy().into_owned();
        mdr_free(p);
        s
    }

    /// Call `mdr_render_page` the way a shell does: owned C strings in, the
    /// returned buffer copied out and released.
    fn page(md: &str, base: &str, lang: &str, editor: bool, toc: bool) -> String {
        let (md, base, lang) = (c(md), c(base), c(lang));
        unsafe { take(mdr_render_page(md.as_ptr(), base.as_ptr(), lang.as_ptr(), editor, toc)) }
    }

    fn update_js(md: &str, base: &str, lang: &str) -> String {
        let (md, base, lang) = (c(md), c(base), c(lang));
        unsafe { take(mdr_render_update_js(md.as_ptr(), base.as_ptr(), lang.as_ptr())) }
    }

    fn detect(md: &str, lang: &str) -> String {
        let (md, lang) = (c(md), c(lang));
        unsafe { take(mdr_detect_lang(md.as_ptr(), lang.as_ptr())) }
    }

    // --- lifetime and memory contract ---

    #[test]
    fn render_page_roundtrip() {
        let md = "# こんにちは\n\ntext";
        let html = page(md, ".", "", false, false);
        assert!(html.contains("<html lang=\"ja\">"));
        assert!(html.contains("こんにちは"));
        assert!(update_js(md, ".", "").contains("setAttribute('lang', \"ja\")"));
        assert_eq!(detect(md, ""), "ja");
    }

    #[test]
    fn null_inputs_do_not_crash() {
        let html = unsafe { take(mdr_render_page(std::ptr::null(), std::ptr::null(), std::ptr::null(), false, false)) };
        // An empty document has no language to detect, so `lang_tag` falls back
        // to the OS locale: this is `<html>` under C/POSIX but `<html lang="ja">`
        // on a Japanese machine. Match the open tag either way — what this test
        // is about is that null pointers produce a page instead of a crash.
        assert!(html.contains("<html"), "no <html> tag in: {}", &html[..html.len().min(200)]);
        assert!(html.contains("</html>"));
        // The other two entry points take the same null treatment.
        let js = unsafe { take(mdr_render_update_js(std::ptr::null(), std::ptr::null(), std::ptr::null())) };
        assert!(js.contains("innerHTML"));
        let _ = unsafe { take(mdr_detect_lang(std::ptr::null(), std::ptr::null())) };
    }

    #[test]
    fn free_ignores_null() {
        // `out()` returns null if a string cannot be converted, and
        // `MdrCore.take` frees whatever it was handed — including that null.
        unsafe { mdr_free(std::ptr::null_mut()) };
    }

    #[test]
    fn the_image_url_policy_can_be_set_from_a_shell() {
        // Process-global, so this test serialises with the others that read it.
        let _guard = crate::core::urlpolicy::lock_policy_for_test();
        let (images, local) = (mdr_remote_images(), mdr_allow_local_http());

        mdr_set_remote_images(false);
        assert!(!mdr_remote_images());
        // A blocked https image becomes a placeholder rather than vanishing.
        let html = page(r#"<img src="https://example.com/a.png">"#, ".", "", false, false);
        assert!(html.contains("img-blocked"), "remote image was not blocked");

        mdr_set_remote_images(true);
        mdr_set_allow_local_http(false);
        assert!(mdr_remote_images() && !mdr_allow_local_http());
        let html = page(r#"<img src="http://192.168.1.5/b.png">"#, ".", "", false, false);
        assert!(html.contains("img-blocked"), "plain-http image was not blocked");

        mdr_set_remote_images(images);
        mdr_set_allow_local_http(local);
    }

    #[test]
    fn version_is_the_crate_version() {
        let v = unsafe { take(mdr_version()) };
        assert_eq!(v, env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn repeated_render_and_free_is_stable() {
        // Edit mode re-renders on a 0.3 s timer, so these two calls run for
        // every pause in typing, each allocating a page Swift hands back.
        for _ in 0..50 {
            assert!(page("# 見出し\n\n本文テキスト", ".", "", false, true).contains("見出し"));
            assert!(update_js("# 見出し", ".", "").contains("見出し"));
        }
    }

    // --- view options ---

    #[test]
    fn view_flags_reach_the_rendered_page() {
        // `editor` and `toc` cross the boundary as C bools. If they were ever
        // swapped or dropped, the phone would silently open the wrong mode.
        assert!(page("# t", ".", "", false, false).contains(r#"<body class="no-toc">"#));
        assert!(page("# t", ".", "", true, false).contains(r#"<body class="no-toc editing">"#));
        assert!(page("# t", ".", "", false, true).contains(r#"<body class="">"#));
        assert!(page("# t", ".", "", true, true).contains(r#"<body class="editing">"#));
    }

    #[test]
    fn document_source_is_escaped_into_the_editor_pane() {
        // The <textarea> carries the raw source; markup left unescaped there
        // would close the element early and truncate the document.
        let html = page("<b>bold</b> & <i>x</i>", ".", "", true, false);
        assert!(html.contains("&lt;b&gt;bold&lt;/b&gt; &amp; &lt;i&gt;x&lt;/i&gt;"));
        // The rendered body still passes raw HTML through (render.unsafe = true).
        assert!(html.contains("<b>bold</b>"));
    }

    #[test]
    fn headings_become_toc_entries() {
        // The iOS TOC sheet scrapes `.sidebar li` and then scrolls to the
        // anchor id, so the list entry and the heading id have to agree.
        let html = page("# Getting Started\n\n## Install", ".", "", false, true);
        assert!(html.contains(r##"<li class="toc-h1"><a href="#getting-started">Getting Started</a></li>"##));
        assert!(html.contains(r##"<li class="toc-h2"><a href="#install">Install</a></li>"##));
        assert!(html.contains(r#"<h1 id="getting-started">"#));
        assert!(html.contains(r#"<h2 id="install">"#));
    }

    // --- language resolution ---

    #[test]
    fn front_matter_beats_explicit_lang_which_beats_detection() {
        let ko = "이것은 한국어 문서입니다.";
        assert_eq!(detect(ko, ""), "ko");
        assert_eq!(detect(ko, "ja"), "ja");
        assert_eq!(detect(&format!("---\nlang: zh-Hant\n---\n{}", ko), "ja"), "zh-Hant");
        assert!(page(ko, ".", "ja", false, false).contains(r#"<html lang="ja">"#));
    }

    #[test]
    fn auto_means_no_explicit_language() {
        // `--lang auto` / `lang auto` in config.kdl reach the shells verbatim.
        assert_eq!(detect("これは日本語です。", "auto"), "ja");
        assert_eq!(detect("这是简体中文的文档。", "auto"), "zh-Hans");
    }

    #[test]
    fn an_unparseable_language_tag_falls_back_to_detection() {
        assert_eq!(detect("これは日本語です。", "xx-YY"), "ja");
    }

    #[test]
    fn update_js_reports_the_same_language_as_the_page() {
        // The page is built once and then updated in place; if the two
        // disagreed, CJK glyphs would change shape mid-edit.
        let md = "---\nlang: zh-Hant\n---\n\nplain text";
        assert!(page(md, ".", "", false, false).contains(r#"<html lang="zh-Hant">"#));
        assert!(update_js(md, ".", "").contains(r#"setAttribute('lang', "zh-Hant")"#));
    }

    // --- live update JS ---

    #[test]
    fn update_js_json_encodes_the_document() {
        // The shells hand this string straight to `evaluateJavaScript` /
        // `evaluate_script`, so every quote, backslash and newline in the
        // document has to survive as an encoded JS string literal.
        //
        // The quote has to come from raw HTML, not from prose: comrak escapes
        // a quote in text to `&quot;`, so `He said "hi"` would prove nothing.
        // `render.unsafe = true` passes an attribute through verbatim, which
        // is the case that actually reaches the JS literal as a raw quote.
        let js = update_js("<span title=\"hi\">x</span>\n\nC:\\path\\to", ".", "");
        assert!(!js.contains('\n'), "update JS must stay on one line: {}", js);
        assert!(js.contains(r#"title=\"hi\""#), "quotes not escaped: {}", js);
        assert!(js.contains(r"C:\\path\\to"), "backslashes not escaped: {}", js);
    }

    // --- base_dir and images ---

    #[test]
    fn relative_images_are_embedded_from_base_dir() {
        // WKWebView loads the page with `baseURL: nil`, so nothing can be
        // fetched from disk afterwards: images must be inlined at render time.
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("pic.png"), PNG).unwrap();
        let html = page("![a](pic.png)", &dir.path().to_string_lossy(), "", false, false);
        assert!(html.contains("data:image/png;base64,"), "image was not inlined");
        assert!(!html.contains(r#"src="pic.png""#));
    }

    #[test]
    fn images_outside_base_dir_are_not_embedded() {
        // A document can name `../secret.png`; embedding it would lift a file
        // the user never opened into the page.
        let dir = tempfile::tempdir().unwrap();
        let sub = dir.path().join("sub");
        std::fs::create_dir(&sub).unwrap();
        std::fs::write(dir.path().join("secret.png"), PNG).unwrap();
        let html = page("![a](../secret.png)", &sub.to_string_lossy(), "", false, false);
        assert!(!html.contains("data:image/png;base64,"), "image escaped base_dir");
        assert!(html.contains(r#"src="../secret.png""#));
    }

    #[test]
    fn a_base_dir_that_does_not_exist_still_renders() {
        // The document's provider (iCloud, a Files extension) can disappear
        // between opening and re-rendering; the page must still come back.
        let html = page("# t\n\n![a](pic.png)", "/no/such/dir", "", false, false);
        assert!(html.contains("</html>"));
        assert!(html.contains(r#"src="pic.png""#));
    }
}
