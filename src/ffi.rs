//! C ABI for native shells (iOS / Android). Strings are UTF-8, NUL-terminated;
//! every `*mut c_char` returned here must be released with [`mdr_free`].

use crate::core::markdown::parse_markdown;
use crate::core::page::{build_html, lang_tag, render_update_js, resolve_local_images, ViewOptions};
use crate::core::toc;
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
    let html = parse_markdown(&md);
    let html = resolve_local_images(&html, Path::new(&base));
    let entries = toc::extract_toc(&md);
    let tag = lang_tag(&md, opt(&lang));
    let opts = ViewOptions { editor, toc, lang: opt(&lang).map(String::from) };
    out(build_html(&html, &entries, &md, &tag, &opts))
}

/// JS that updates an already loaded page (body, TOC, lang) from new markdown.
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
#[no_mangle]
pub unsafe extern "C" fn mdr_detect_lang(markdown: *const c_char, lang: *const c_char) -> *mut c_char {
    let md = arg(markdown);
    let lang = arg(lang);
    out(lang_tag(&md, opt(&lang)))
}

/// Library version string.
#[no_mangle]
pub extern "C" fn mdr_version() -> *mut c_char {
    out(env!("CARGO_PKG_VERSION").to_string())
}

/// Release a string returned by this library.
#[no_mangle]
pub unsafe extern "C" fn mdr_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn take(p: *mut c_char) -> String {
        let s = CStr::from_ptr(p).to_string_lossy().into_owned();
        mdr_free(p);
        s
    }

    #[test]
    fn render_page_roundtrip() {
        let md = CString::new("# こんにちは\n\ntext").unwrap();
        let base = CString::new(".").unwrap();
        let lang = CString::new("").unwrap();
        let html = unsafe { take(mdr_render_page(md.as_ptr(), base.as_ptr(), lang.as_ptr(), false, false)) };
        assert!(html.contains("<html lang=\"ja\">"));
        assert!(html.contains("こんにちは"));
        let js = unsafe { take(mdr_render_update_js(md.as_ptr(), base.as_ptr(), lang.as_ptr())) };
        assert!(js.contains("setAttribute('lang', \"ja\")"));
        let tag = unsafe { take(mdr_detect_lang(md.as_ptr(), lang.as_ptr())) };
        assert_eq!(tag, "ja");
    }

    #[test]
    fn null_inputs_do_not_crash() {
        let html = unsafe { take(mdr_render_page(std::ptr::null(), std::ptr::null(), std::ptr::null(), false, false)) };
        assert!(html.contains("<html>"));
    }
}
