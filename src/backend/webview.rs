#[cfg(not(any(target_os = "ios", target_os = "android")))]
use muda::{Menu, PredefinedMenuItem, Submenu};
use std::path::{Path, PathBuf};
use std::sync::mpsc::Receiver;
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoop, EventLoopBuilder};
use tao::window::WindowBuilder;
use wry::WebViewBuilder;

use crate::core::markdown::parse_markdown;
use crate::core::page::{
    build_html, lang_tag, percent_decode, render_update_js, resolve_local_images,
};
pub use crate::core::page::ViewOptions;
use crate::core::toc;
use crate::vlog;

/// Shown when the app is launched without a file (e.g. double-clicking Mdr.app).
/// The window is a live drop target, so this doubles as the instructions.
const WELCOME_MD: &str = r#"# mdr

**Markdown ファイルをこのウィンドウにドロップ**すると表示します。
*Drop a Markdown file onto this window to open it.*

- 対応拡張子 / extensions: `.md` `.markdown` `.mdown` `.mkd` `.mdx` `.txt`
- Finder から「このアプリケーションで開く」でも開けます
- ターミナルからは `mdr <file.md>` — オプションは `mdr --help`
"#;

/// Extensions accepted by drag & drop / the Finder open handler.
const DOC_EXTS: [&str; 6] = ["md", "markdown", "mdown", "mkd", "mdx", "txt"];

fn is_markdown_path(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| DOC_EXTS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// Pick the first Markdown-ish path out of a drop / open-document payload.
fn first_doc(paths: &[PathBuf]) -> Option<PathBuf> {
    paths
        .iter()
        .find(|p| p.is_file() && is_markdown_path(p))
        .cloned()
}

/// Messages sent from the page (via `window.ipc.postMessage`) or from a file
/// drop / Finder "open document" event to the event loop.
#[derive(Debug)]
enum UserEvent {
    /// Re-render the preview from unsaved editor text.
    Preview(String),
    /// Write editor text back to the opened file.
    Save(String),
    /// Replace the displayed document (drag & drop, or Finder open).
    Open(PathBuf),
    /// A link clicked in the page. Relative hrefs are resolved against the
    /// *current* document's directory, so links keep working after a switch.
    OpenHref(String),
}

/// The document currently shown in the window. `path` is `None` for the
/// welcome screen, where there is nothing to watch and nothing to save to.
struct Doc {
    path: Option<PathBuf>,
    base_dir: PathBuf,
    content: String,
    watcher: Option<Receiver<()>>,
}

impl Doc {
    /// Load `path`, or build the welcome screen when `path` is `None`.
    fn load(path: Option<&Path>) -> Result<Self, Box<dyn std::error::Error>> {
        let Some(path) = path else {
            return Ok(Doc {
                path: None,
                base_dir: std::env::current_dir().unwrap_or_default(),
                content: WELCOME_MD.to_string(),
                watcher: None,
            });
        };
        // Canonicalize first so parent() always gives an absolute directory.
        // Without this, a bare filename like "README.md" gives parent() = "" (empty),
        // which breaks relative image resolution when CWD differs from expected.
        let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| {
            std::env::current_dir()
                .map(|cwd| cwd.join(path))
                .unwrap_or_else(|_| path.to_path_buf())
        });
        let base_dir = canonical
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
        let content = std::fs::read_to_string(&canonical)?;
        let watcher = crate::core::watcher::watch_file(&canonical).ok();
        vlog!("webview: file_path={}", canonical.display());
        vlog!("webview: base_dir={}", base_dir.display());
        vlog!("webview: markdown_content length={} bytes", content.len());
        Ok(Doc { path: Some(canonical), base_dir, content, watcher })
    }

    /// Resolve a link href from the page against this document's directory.
    /// Returns `None` unless it names an existing Markdown file.
    ///
    /// Unlike images, `../` is allowed here: images are embedded silently, so
    /// they stay inside `base_dir`, whereas following a link is an explicit
    /// user click and sibling-directory links are normal in a notes tree. The
    /// opened file becomes the new `base_dir`, so its own images re-scope to it.
    fn resolve_href(&self, href: &str) -> Option<PathBuf> {
        // Strip the #fragment / ?query a Markdown link may carry.
        let path_part = href.split(['#', '?']).next().unwrap_or("");
        if path_part.is_empty() {
            return None;
        }
        let target = self.base_dir.join(percent_decode(path_part));
        if !target.is_file() || !is_markdown_path(&target) {
            return None;
        }
        target.canonicalize().ok()
    }

    fn title(&self) -> String {
        match &self.path {
            Some(p) => format!("mdr - {}", p.display()),
            None => "mdr".to_string(),
        }
    }

    /// Render the full page. The welcome screen is always viewer-only: there is
    /// no file behind it, so editing it would have nowhere to save.
    fn html(&self, opts: &ViewOptions) -> String {
        let html_body = parse_markdown(&self.content);
        vlog!("webview: html_body length={} bytes", html_body.len());
        // In verbose mode, dump all <img> tags found in the HTML
        if crate::core::verbose() {
            use std::sync::OnceLock;
            static RE_VERBOSE: OnceLock<regex::Regex> = OnceLock::new();
            let re = RE_VERBOSE.get_or_init(|| regex::Regex::new(r#"<img\s[^>]*?>"#).unwrap());
            for cap in re.find_iter(&html_body) {
                let tag = cap.as_str();
                let shown = if tag.len() > 200 { &tag[..200] } else { tag };
                vlog!("webview: found <img> tag: {}", shown);
            }
        }
        let html_body = resolve_local_images(&html_body, &self.base_dir);
        let toc_entries = toc::extract_toc(&self.content);
        let doc_lang = lang_tag(&self.content, opts.lang.as_deref());
        vlog!("webview: lang={:?}", doc_lang);
        let opts = if self.path.is_some() {
            opts.clone()
        } else {
            ViewOptions { editor: false, ..opts.clone() }
        };
        build_html(&html_body, &toc_entries, &self.content, &doc_lang, &opts)
    }
}

/// Open `file_path` in a window, or the welcome/drop screen when `None`.
pub fn run(file_path: Option<PathBuf>, opts: ViewOptions) -> Result<(), Box<dyn std::error::Error>> {
    let mut doc = Doc::load(file_path.as_deref())?;
    let full_html = doc.html(&opts);
    let explicit_lang = opts.lang.clone();

    let (icon_rgba, icon_w, icon_h) = crate::core::icon::load_icon_rgba();

    let event_loop: EventLoop<UserEvent> = EventLoopBuilder::<UserEvent>::with_user_event().build();
    let proxy = event_loop.create_proxy();
    let ipc_handler = move |req: wry::http::Request<String>| {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(req.body()) else {
            return;
        };
        let text = v["text"].as_str().unwrap_or("").to_string();
        let ev = match v["cmd"].as_str().unwrap_or("") {
            "preview" => UserEvent::Preview(text),
            "save" => UserEvent::Save(text),
            "open" => UserEvent::OpenHref(text),
            _ => return,
        };
        let _ = proxy.send_event(ev);
    };

    // Files dropped onto the webview. The webview covers the whole window, so
    // this — not tao's WindowEvent::DroppedFile — is what fires on macOS.
    let drop_proxy = event_loop.create_proxy();
    let drag_drop_handler = move |ev: wry::DragDropEvent| match ev {
        wry::DragDropEvent::Drop { paths, .. } => match first_doc(&paths) {
            Some(p) => {
                let _ = drop_proxy.send_event(UserEvent::Open(p));
                true
            }
            // Not a Markdown file: let the page handle it (e.g. image paste targets).
            None => false,
        },
        _ => false,
    };

    // Create a native Edit menu so that Cmd+C/Ctrl+C/V/X/A work on all desktop platforms
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    let menu = {
        let menu = Menu::new();
        let edit_menu = Submenu::new("Edit", true);
        let _ = edit_menu.append_items(&[
            &PredefinedMenuItem::cut(None),
            &PredefinedMenuItem::copy(None),
            &PredefinedMenuItem::paste(None),
            &PredefinedMenuItem::select_all(None),
        ]);
        let _ = menu.append(&edit_menu);
        menu
    };

    let builder = WindowBuilder::new().with_title(doc.title());
    // Desktop: fixed initial size + icon. Mobile: the window is the whole screen.
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    let builder = builder
        .with_inner_size(tao::dpi::LogicalSize::new(1100.0, 900.0))
        .with_window_icon(Some(
            tao::window::Icon::from_rgba(icon_rgba, icon_w, icon_h).unwrap(),
        ));
    #[cfg(any(target_os = "ios", target_os = "android"))]
    let _ = (icon_rgba, icon_w, icon_h);
    let window = builder.build(&event_loop)?;

    // On macOS, init the menu for the app so Cmd+C/V/X/A work via the responder chain
    #[cfg(target_os = "macos")]
    menu.init_for_nsapp();

    #[cfg(target_os = "linux")]
    let webview = {
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;
        let vbox = window.default_vbox().unwrap();
        WebViewBuilder::new()
            .with_html(&full_html)
            .with_clipboard(true)
            .with_devtools(true)
            .with_ipc_handler(ipc_handler)
            .with_drag_drop_handler(drag_drop_handler)
            .build_gtk(vbox)?
    };
    #[cfg(not(target_os = "linux"))]
    let webview = WebViewBuilder::new()
        .with_html(&full_html)
        .with_clipboard(true)
        .with_devtools(true)
        .with_ipc_handler(ipc_handler)
        .with_drag_drop_handler(drag_drop_handler)
        .build(&window)?;

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        // Check for file changes (external edits or our own save)
        if doc.watcher.as_ref().is_some_and(|rx| rx.try_recv().is_ok()) {
            while doc.watcher.as_ref().is_some_and(|rx| rx.try_recv().is_ok()) {}
            if let Some(path) = doc.path.clone() {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    doc.content = content.clone();
                    let mut js = render_update_js(&content, &doc.base_dir, explicit_lang.as_deref());
                    let src_json = serde_json::to_string(&content).unwrap_or_default();
                    js.push_str(&format!(
                        " if (window.__mdrSetEditor) __mdrSetEditor({});",
                        src_json.replace("</", "<\\/")
                    ));
                    let _ = webview.evaluate_script(&js);
                }
            }
        }

        match event {
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => *control_flow = ControlFlow::Exit,
            // Finder "Open With" / `open -a Mdr file.md` on an already-running app,
            // and the launch-time open event for a double-clicked document.
            Event::Opened { urls } => {
                let paths: Vec<PathBuf> = urls.iter().filter_map(|u| u.to_file_path().ok()).collect();
                if let Some(p) = first_doc(&paths) {
                    open_doc(&mut doc, &p, &opts, &window, &webview);
                }
            }
            // Fallback for platforms where the drop lands on the window, not the webview.
            Event::WindowEvent {
                event: WindowEvent::DroppedFile(path),
                ..
            } => {
                if let Some(p) = first_doc(std::slice::from_ref(&path)) {
                    open_doc(&mut doc, &p, &opts, &window, &webview);
                }
            }
            Event::UserEvent(UserEvent::Open(path)) => {
                open_doc(&mut doc, &path, &opts, &window, &webview);
            }
            Event::UserEvent(UserEvent::OpenHref(href)) => {
                if let Some(path) = doc.resolve_href(&href) {
                    open_doc(&mut doc, &path, &opts, &window, &webview);
                } else {
                    vlog!("webview: ignoring link {:?}", href);
                }
            }
            Event::UserEvent(UserEvent::Preview(text)) => {
                let js = render_update_js(&text, &doc.base_dir, explicit_lang.as_deref());
                let _ = webview.evaluate_script(&js);
            }
            Event::UserEvent(UserEvent::Save(text)) => {
                let js = match &doc.path {
                    // The welcome screen has no file behind it; report it instead
                    // of silently discarding the text.
                    None => {
                        let msg = serde_json::to_string("no file open — drop a Markdown file first")
                            .unwrap_or_default();
                        format!("if (window.__mdrSaved) __mdrSaved({});", msg)
                    }
                    Some(path) => match std::fs::write(path, &text) {
                        Ok(()) => {
                            vlog!("webview: saved {} bytes to {}", text.len(), path.display());
                            "if (window.__mdrSaved) __mdrSaved(null);".to_string()
                        }
                        Err(e) => {
                            let msg = serde_json::to_string(&e.to_string()).unwrap_or_default();
                            format!("if (window.__mdrSaved) __mdrSaved({});", msg)
                        }
                    },
                };
                let _ = webview.evaluate_script(&js);
            }
            _ => {}
        }
    });
}

/// Swap the window over to `path`, reloading the page from scratch so the TOC,
/// editor pane and language attribute all follow the new document.
fn open_doc(
    doc: &mut Doc,
    path: &Path,
    opts: &ViewOptions,
    window: &tao::window::Window,
    webview: &wry::WebView,
) {
    match Doc::load(Some(path)) {
        Ok(new_doc) => {
            *doc = new_doc;
            window.set_title(&doc.title());
            let _ = webview.load_html(&doc.html(opts));
        }
        Err(e) => {
            vlog!("webview: failed to open {}: {}", path.display(), e);
            let msg = serde_json::to_string(&format!("cannot open {}: {}", path.display(), e))
                .unwrap_or_default();
            let _ = webview.evaluate_script(&format!(
                "if (window.__mdrSaved) __mdrSaved({});",
                msg
            ));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markdown_extensions_are_matched_case_insensitively() {
        assert!(is_markdown_path(Path::new("a.md")));
        assert!(is_markdown_path(Path::new("a.MD")));
        assert!(is_markdown_path(Path::new("a.Markdown")));
        assert!(!is_markdown_path(Path::new("a.png")));
        assert!(!is_markdown_path(Path::new("noext")));
    }

    /// Relative links resolve against the *current* document's directory, so a
    /// link followed from a subdirectory keeps working after the switch.
    #[test]
    fn hrefs_resolve_against_the_current_document() {
        let tmp = std::env::temp_dir().join(format!("mdr-href-{}", std::process::id()));
        let sub = tmp.join("sub");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(tmp.join("a.md"), "# a").unwrap();
        std::fs::write(sub.join("b.md"), "# b").unwrap();
        std::fs::write(sub.join("pic png.md"), "# spaces").unwrap();
        std::fs::write(tmp.join("note.png"), "not markdown").unwrap();

        let a = Doc::load(Some(&tmp.join("a.md"))).unwrap();
        assert!(a.resolve_href("./sub/b.md").is_some());
        assert!(a.resolve_href("sub/b.md#heading").is_some());
        // Not a document, or not there at all.
        assert!(a.resolve_href("note.png").is_none());
        assert!(a.resolve_href("missing.md").is_none());
        assert!(a.resolve_href("").is_none());

        // After following the link, `../a.md` must resolve from sub/, not from tmp/.
        let b = Doc::load(Some(&sub.join("b.md"))).unwrap();
        assert!(b.resolve_href("../a.md").is_some());
        assert!(b.resolve_href("a.md").is_none());
        // Percent-encoded spaces (comrak encodes them in hrefs).
        assert!(b.resolve_href("pic%20png.md").is_some());

        std::fs::remove_dir_all(&tmp).ok();
    }

    /// Switching documents has to move the rendering base with it, not just the
    /// link resolution. `resolve_href` proves a link points somewhere; this
    /// proves the page rendered after the switch reads images from the new
    /// document's directory. The two used to be the same line of code, and the
    /// class comment on `Doc` says why they must stay together.
    #[test]
    fn rendering_follows_the_document_across_a_switch() {
        const PNG: &[u8] = &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        let tmp = std::env::temp_dir().join(format!("mdr-switch-{}", std::process::id()));
        let sub = tmp.join("sub");
        std::fs::create_dir_all(&sub).unwrap();
        // The same relative reference, `pic.png`, in both documents — but only
        // the one next to each document should ever be found.
        std::fs::write(tmp.join("a.md"), "# a\n\n![p](pic.png)").unwrap();
        std::fs::write(sub.join("b.md"), "# b\n\n![p](pic.png)").unwrap();
        std::fs::write(sub.join("pic.png"), PNG).unwrap();

        let opts = ViewOptions::default();

        // a.md has no pic.png beside it, so nothing may be inlined.
        let a = Doc::load(Some(&tmp.join("a.md"))).unwrap();
        assert!(
            !a.html(&opts).contains("data:image/png;base64,"),
            "a.md must not pick up sub/pic.png"
        );

        // Following the link to sub/b.md moves the base with it.
        let b = Doc::load(Some(&sub.join("b.md"))).unwrap();
        assert!(
            b.html(&opts).contains("data:image/png;base64,"),
            "after the switch, images must resolve from the new document's directory"
        );
        assert!(b.title().ends_with("b.md"), "the window title tracks the open document");

        std::fs::remove_dir_all(&tmp).ok();
    }

    #[test]
    fn welcome_screen_has_no_file_and_never_starts_in_editor_mode() {
        let doc = Doc::load(None).unwrap();
        assert!(doc.path.is_none());
        assert!(doc.watcher.is_none());
        let html = doc.html(&ViewOptions { editor: true, toc: false, lang: None });
        assert!(!html.contains("class=\"editing"));
    }
}
