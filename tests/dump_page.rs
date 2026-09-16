//! Writes the rendered page to $MDR_DUMP_HTML, for inspecting the markup
//! (About dialog, menu) without driving a GUI. No-op when the var is unset.
#[cfg(feature = "svg")]
#[test]
fn dump_page_html() {
    let Ok(path) = std::env::var("MDR_DUMP_HTML") else { return };
    let html = mdr::core::page::build_html(
        "<h1>About dump</h1>",
        &[],
        "# About dump",
        "",
        &mdr::core::page::ViewOptions::default(),
    );
    std::fs::write(&path, html).unwrap();
    eprintln!("wrote {}", path);
}
