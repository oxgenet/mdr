#[cfg(not(any(target_os = "ios", target_os = "android")))]
use muda::{Menu, PredefinedMenuItem, Submenu};
use std::path::PathBuf;
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoop, EventLoopBuilder};
use tao::window::WindowBuilder;
use wry::WebViewBuilder;

use crate::core::markdown::parse_markdown;
use crate::core::page::{build_html, lang_tag, render_update_js, resolve_local_images};
pub use crate::core::page::ViewOptions;
use crate::core::toc;
use crate::vlog;

/// Messages sent from the page (via `window.ipc.postMessage`) to the event loop.
#[derive(Debug)]
enum UserEvent {
    /// Re-render the preview from unsaved editor text.
    Preview(String),
    /// Write editor text back to the opened file.
    Save(String),
}

pub fn run(file_path: PathBuf, opts: ViewOptions) -> Result<(), Box<dyn std::error::Error>> {
    // Canonicalize the file path first so parent() always gives an absolute directory.
    // Without this, a bare filename like "README.md" gives parent() = "" (empty),
    // which breaks relative image resolution when CWD differs from expected.
    let canonical_file = std::fs::canonicalize(&file_path).unwrap_or_else(|_| {
        // If canonicalize fails, try current_dir + file_path
        std::env::current_dir()
            .map(|cwd| cwd.join(&file_path))
            .unwrap_or_else(|_| file_path.clone())
    });
    let base_dir = canonical_file
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
    let markdown_content = std::fs::read_to_string(&file_path)?;
    vlog!("webview: file_path={}", file_path.display());
    vlog!("webview: base_dir={}", base_dir.display());
    vlog!(
        "webview: markdown_content length={} bytes",
        markdown_content.len()
    );
    let html_body = parse_markdown(&markdown_content);
    vlog!("webview: html_body length={} bytes", html_body.len());
    // In verbose mode, dump all <img> tags found in the HTML
    if crate::core::verbose() {
        use std::sync::OnceLock;
        static RE_VERBOSE: OnceLock<regex::Regex> = OnceLock::new();
        let re_verbose = RE_VERBOSE.get_or_init(|| regex::Regex::new(r#"<img\s[^>]*?>"#).unwrap());
        for cap in re_verbose.find_iter(&html_body) {
            let tag = cap.as_str();
            if tag.len() > 200 {
                vlog!("webview: found <img> tag: {}...", &tag[..200]);
            } else {
                vlog!("webview: found <img> tag: {}", tag);
            }
        }
    }
    let html_body = resolve_local_images(&html_body, &base_dir);
    let toc_entries = toc::extract_toc(&markdown_content);
    let doc_lang = lang_tag(&markdown_content, opts.lang.as_deref());
    vlog!("webview: lang={:?}", doc_lang);
    let full_html = build_html(&html_body, &toc_entries, &markdown_content, &doc_lang, &opts);
    let explicit_lang = opts.lang.clone();

    let watcher_rx = crate::core::watcher::watch_file(&file_path)?;

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
            _ => return,
        };
        let _ = proxy.send_event(ev);
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

    let builder = WindowBuilder::new().with_title(format!("mdr - {}", file_path.display()));
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
            .build_gtk(vbox)?
    };
    #[cfg(not(target_os = "linux"))]
    let webview = WebViewBuilder::new()
        .with_html(&full_html)
        .with_clipboard(true)
        .with_devtools(true)
        .with_ipc_handler(ipc_handler)
        .build(&window)?;

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        // Check for file changes (external edits or our own save)
        if watcher_rx.try_recv().is_ok() {
            while watcher_rx.try_recv().is_ok() {}
            if let Ok(content) = std::fs::read_to_string(&file_path) {
                let mut js = render_update_js(&content, &base_dir, explicit_lang.as_deref());
                let src_json = serde_json::to_string(&content).unwrap_or_default();
                js.push_str(&format!(
                    " if (window.__mdrSetEditor) __mdrSetEditor({});",
                    src_json.replace("</", "<\\/")
                ));
                let _ = webview.evaluate_script(&js);
            }
        }

        match event {
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => *control_flow = ControlFlow::Exit,
            Event::UserEvent(UserEvent::Preview(text)) => {
                let js = render_update_js(&text, &base_dir, explicit_lang.as_deref());
                let _ = webview.evaluate_script(&js);
            }
            Event::UserEvent(UserEvent::Save(text)) => {
                let js = match std::fs::write(&file_path, &text) {
                    Ok(()) => {
                        vlog!("webview: saved {} bytes to {}", text.len(), file_path.display());
                        "if (window.__mdrSaved) __mdrSaved(null);".to_string()
                    }
                    Err(e) => {
                        let msg = serde_json::to_string(&e.to_string()).unwrap_or_default();
                        format!("if (window.__mdrSaved) __mdrSaved({});", msg)
                    }
                };
                let _ = webview.evaluate_script(&js);
            }
            _ => {}
        }
    });
}

