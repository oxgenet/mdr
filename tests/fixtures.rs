//! Renders every end-to-end fixture in `tests/samples/` and checks the
//! behaviour each one is named for.
//!
//! These are not golden-file tests. Exact output moves whenever the CSS or the
//! Mermaid renderer does, and pinning it would mean rewriting expectations for
//! every cosmetic change. What is pinned is that each document survives — a
//! complete page comes out, nothing panics — and that the specific behaviour
//! the fixture exists to demonstrate still holds.
//!
//! Several fixtures are deliberately wrong (a mislabelled image, a missing
//! file, `javascript:` hrefs). That is the point: the renderer has to cope.

#![cfg(feature = "svg")]

use mdr::core::page::render_page;
use std::path::{Path, PathBuf};

fn samples() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/samples")
}

/// Render a fixture the way a shell does: its own directory as `base_dir`.
fn render(relative: &str) -> String {
    let path = samples().join(relative);
    let markdown = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read fixture {}: {e}", path.display()));
    let base = path.parent().expect("fixture has a parent directory");
    render_page(&markdown, base, None, false, true)
}

/// Just the rendered document, without the surrounding chrome.
///
/// The page also embeds the untouched source in the editor `<textarea>`, so a
/// search over the whole page cannot tell "this was rendered" from "this was
/// offered for editing" — front matter legitimately appears in the second.
fn body_of(html: &str) -> &str {
    let start = html.find(r#"<div class="content">"#).expect("no content block");
    let end = html[start..].find(r#"<div id="kebab">"#).expect("no chrome after content");
    &html[start..start + end]
}

fn assert_complete_page(html: &str, what: &str) {
    assert!(html.contains("<html"), "{what}: no opening <html>");
    assert!(html.contains("</html>"), "{what}: page was truncated");
    assert!(html.contains("<div class=\"content\">"), "{what}: no content block");
}

/// Every fixture must render, including the deliberately broken ones.
#[test]
fn every_fixture_renders_completely() {
    let mut count = 0;
    for entry in walk(&samples()) {
        let relative = entry.strip_prefix(samples()).unwrap().to_string_lossy().replace('\\', "/");
        let html = render(&relative);
        assert_complete_page(&html, &relative);
        // A page that rendered nothing but chrome means the body was dropped.
        assert!(html.len() > 5_000, "{relative}: suspiciously small page ({} bytes)", html.len());
        count += 1;
    }
    assert!(count >= 8, "expected the full fixture set, found {count} documents");
}

// --- markdown.md ---

#[test]
fn front_matter_is_stripped_and_its_language_wins() {
    let html = render("e2e/markdown.md");
    // Only CJK tags mean anything to core::lang — the machinery exists to pick
    // glyph shapes — so the fixture declares zh-Hant, which detection would
    // never choose for a mostly-English document carrying Japanese and Korean.
    assert!(html.contains(r#"<html lang="zh-Hant">"#), "front matter lang ignored");
    // The block must not be rendered as text. It does still appear in the
    // editor textarea, which is correct — that pane holds the real source.
    assert!(
        !body_of(&html).contains("author: mdr test suite"),
        "front matter was rendered into the document body",
    );
    assert!(html.contains("author: mdr test suite"), "the editor lost the front matter");
}

#[test]
fn colliding_headings_produce_colliding_anchors() {
    // Two "### Setup" headings slugify identically, so the table of contents
    // gets two entries pointing at one anchor. Documented rather than fixed:
    // changing it would move every existing anchor.
    let html = render("e2e/markdown.md");
    // `r#"..."#` cannot hold `href="#`: the `"#` closes the literal early, so
    // this needs the longer delimiter.
    assert_eq!(html.matches(r##"href="#setup""##).count(), 2, "expected two TOC entries for Setup");
}

#[test]
fn gfm_constructs_all_render() {
    let html = render("e2e/markdown.md");
    for (needle, what) in [
        ("<table>", "table"),
        ("<del>", "strikethrough"),
        ("checkbox", "task list"),
        ("footnotes", "footnotes"),
        ("<details>", "raw HTML passthrough"),
        ("<blockquote>", "blockquote"),
    ] {
        assert!(html.contains(needle), "{what} did not render");
    }
}

// --- images.md ---

#[test]
fn local_images_embed_and_bad_ones_do_not() {
    let html = render("e2e/images.md");

    assert!(html.contains("data:image/png;base64,"), "a valid local PNG was not embedded");
    // Rasterised SVG arrives as a PNG data URI too, never as inline <svg>,
    // so a script inside it cannot execute.
    assert!(!html.contains("<svg xmlns"), "an SVG file was inlined rather than rasterised");

    // Contents that do not match the extension are refused.
    assert!(html.contains("Invalid image"), "a mislabelled image was embedded anyway");
    // A missing file keeps its original reference and its alt text.
    assert!(html.contains(r#"src="assets/nope.png""#), "a missing image was altered");
    // `../` escapes the document's directory and must not be embedded.
    assert!(html.contains(r#"src="../lang/test.png""#), "an image outside base_dir was embedded");
}

#[test]
fn the_remote_image_policy_holds_across_a_whole_document() {
    let html = render("e2e/images.md");

    // Allowed: https anywhere, and plain http only to local/private targets.
    for allowed in [
        "https://example.com/chart.png",
        "http://192.168.1.10/photo.png",
        "http://localhost:3000/preview.png",
        "http://nas.local/share/image.png",
    ] {
        assert!(html.contains(&format!(r#"src="{allowed}""#)), "{allowed} should have been allowed");
    }
    assert!(html.contains(r#"loading="lazy""#), "allowed remote images should load lazily");

    // Blocked: public http, odd ports, credentials, other schemes.
    for blocked in [
        "http://example.com/insecure.png",
        "http://192.168.1.10:22/photo.png",
        "http://user:password@192.168.1.10/photo.png",
        "ftp://example.com/image.png",
        "http://internal.corp.example/logo.png",
    ] {
        assert!(!html.contains(&format!(r#"src="{blocked}""#)), "{blocked} should have been blocked");
    }
    assert!(html.contains("img-blocked"), "blocked images should become placeholders");
}

// --- links.md ---

#[test]
fn dangerous_link_schemes_are_neutralised_in_the_page() {
    // The document deliberately contains javascript: hrefs, both from Markdown
    // and as raw HTML. The page's click handler refuses to act on them; this
    // pins that guard, since removing it would be silent and the Android
    // shell exposes an ipc bridge to page scripts.
    let html = render("e2e/links.md");
    assert!(
        html.contains("javascript|data|vbscript"),
        "the page no longer guards against dangerous link schemes",
    );
}

#[test]
fn every_link_shape_survives_rendering() {
    let html = render("e2e/links.md");
    for (needle, what) in [
        ("https://example.com/reference", "reference-style link"),
        ("https://example.com/autolink", "autolink"),
        ("mailto:someone@example.com", "mailto"),
        ("%20path%20with%20spaces", "percent-encoded path"),
        ("markdown.md", "relative document link"),
    ] {
        assert!(html.contains(needle), "{what} was lost");
    }
}

// --- diagrams.md ---

#[test]
fn every_mermaid_block_is_processed_one_way_or_another() {
    let html = render("e2e/diagrams.md");
    // Nothing may survive as an unprocessed mermaid code fence: each block is
    // either a rendered diagram or handed to the bundled mermaid.js.
    assert!(
        !html.contains(r#"class="language-mermaid""#),
        "a mermaid block was left unprocessed",
    );
    assert!(
        html.contains("mermaid-diagram") || html.contains(r#"class="mermaid""#),
        "no diagram was produced at all",
    );
    // Malformed blocks must not take the rest of the document with them.
    assert!(html.contains("Gantt"), "the document stopped at a broken diagram");
}

/// Every `.md` under `tests/samples`, recursively.
fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(current) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&current) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md") {
                found.push(path);
            }
        }
    }
    found.sort();
    found
}
