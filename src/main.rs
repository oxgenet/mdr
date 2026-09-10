use mdr::{backend, core};

use clap::Parser;
use std::io::{self, IsTerminal, Read};
use std::path::PathBuf;
use std::process;

#[derive(Parser)]
#[command(name = "mdr", version, about = "Lightweight Markdown viewer with live reload")]
struct Cli {
    /// Markdown file to render (use '-' or pipe via stdin)
    file: Option<PathBuf>,

    /// Rendering backend to use: egui (native GUI), webview (HTML), tui (terminal)
    #[arg(short, long, value_parser = parse_backend)]
    backend: Option<String>,

    /// Enable verbose logging (image resolution, mermaid rendering, etc.)
    #[arg(short, long)]
    verbose: bool,

    /// Path to config file [default: ~/.config/mdr/config.kdl]
    #[arg(long, value_name = "PATH")]
    config: Option<PathBuf>,

    /// List available backends and exit
    #[arg(long)]
    list_backends: bool,

    /// Create a default config file and exit
    #[arg(long)]
    init: bool,

    /// Start in editor mode (webview backend). Default is viewer mode.
    #[arg(short = 'e', long)]
    edit: bool,

    /// Show the table of contents sidebar at startup (webview backend)
    #[arg(long)]
    toc: bool,

    /// Document language for CJK rendering: auto, ja, zh-Hans, zh-Hant, ko
    /// (front matter `lang:` in the document takes precedence)
    #[arg(long, value_name = "TAG")]
    lang: Option<String>,

    /// Do not load images from http(s) URLs
    #[arg(long)]
    no_remote_images: bool,

    /// Do not allow plain-http images even for localhost / private addresses
    #[arg(long)]
    no_local_http: bool,

    /// Open an empty window without a file; drop a Markdown file onto it
    /// (webview backend). This is what Mdr.app does when launched from Finder.
    #[arg(short = 'n', long)]
    new: bool,

    /// Symlink this executable as `mdr` into a bin directory and exit, so the
    /// copy inside Mdr.app is reachable from a terminal as plain `mdr`.
    #[arg(long)]
    install_cli: bool,

    /// Directory for --install-cli [default: ~/.local/bin]
    #[arg(long, value_name = "DIR")]
    prefix: Option<PathBuf>,
}

/// Where `--install-cli` puts the symlink: user-writable, needs no sudo, and
/// is on PATH by default on most shells.
#[cfg(unix)]
fn default_bin_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default()
        .join(".local/bin")
}

/// Symlink this executable as `<dir>/mdr`, so `mdr` on the command line and
/// Mdr.app in the Dock are the same build. Never exits successfully without
/// having created the link.
#[cfg(unix)]
fn install_cli(prefix: Option<PathBuf>) -> ! {
    let exe = std::env::current_exe().unwrap_or_else(|e| {
        eprintln!("Error: cannot locate this executable: {}", e);
        process::exit(1);
    });
    let dir = prefix.unwrap_or_else(default_bin_dir);
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("Error: cannot create {}: {}", dir.display(), e);
        process::exit(1);
    }
    let link = dir.join("mdr");

    // Replace a symlink we (or a previous install) made, but never clobber a
    // real binary someone installed by other means.
    match std::fs::symlink_metadata(&link) {
        Ok(m) if m.file_type().is_symlink() => {
            if let Err(e) = std::fs::remove_file(&link) {
                eprintln!("Error: cannot replace {}: {}", link.display(), e);
                process::exit(1);
            }
        }
        Ok(_) => {
            eprintln!("Error: {} already exists and is not a symlink.", link.display());
            eprintln!("Remove it first, or pass --prefix <DIR> to install elsewhere.");
            process::exit(1);
        }
        Err(_) => {}
    }

    if let Err(e) = std::os::unix::fs::symlink(&exe, &link) {
        eprintln!("Error: cannot link {}: {}", link.display(), e);
        if e.kind() == io::ErrorKind::PermissionDenied {
            eprintln!("Try: sudo mdr --install-cli --prefix {}", dir.display());
        }
        process::exit(1);
    }
    println!("{} -> {}", link.display(), exe.display());

    let on_path = std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).any(|d| d == dir))
        .unwrap_or(false);
    if on_path {
        println!("{} is on PATH — `mdr` is ready to use.", dir.display());
    } else {
        println!();
        println!("{} is not on PATH. Add it:", dir.display());
        println!("  echo 'export PATH=\"{}:$PATH\"' >> ~/.zshrc && exec zsh", dir.display());
    }
    process::exit(0);
}

/// True when this process is `Mdr.app/Contents/MacOS/mdr`, i.e. launched from
/// Finder/Dock rather than a shell. Such a launch has no arguments and no
/// usable stdin, so it must open the empty drop window instead of failing.
fn launched_from_app_bundle() -> bool {
    if !cfg!(target_os = "macos") {
        return false;
    }
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|d| d.to_path_buf()))
        .is_some_and(|dir| dir.ends_with("Contents/MacOS"))
}

fn print_backends() {
    fn status(compiled: bool) -> &'static str {
        if compiled { "✓ compiled" } else { "✗ not compiled" }
    }
    eprintln!("Available backends:");
    eprintln!("  egui      Native GUI window (OpenGL)            [{}]", status(cfg!(feature = "egui-backend")));
    eprintln!("  webview   System webview (WebKit/WebView2)      [{}]", status(cfg!(feature = "webview-backend")));
    eprintln!("  tui       Terminal UI with image support         [{}]", status(cfg!(feature = "tui-backend")));
    eprintln!("  auto      Auto-detect best available (default)");
}

fn parse_backend(s: &str) -> Result<String, String> {
    match s {
        "auto" | "egui" | "webview" | "tui" => Ok(s.to_string()),
        _ => Err(format!("unknown backend '{}', expected 'auto', 'egui', 'webview', or 'tui'", s)),
    }
}

/// Auto-detect the best backend for the current environment.
fn detect_backend() -> &'static str {
    // If no DISPLAY/WAYLAND and we have a TTY → TUI
    // If SSH session → TUI
    // Otherwise → egui (or first available GUI backend)
    let is_ssh = std::env::var("SSH_CONNECTION").is_ok() || std::env::var("SSH_TTY").is_ok();
    let has_display = std::env::var("DISPLAY").is_ok()
        || std::env::var("WAYLAND_DISPLAY").is_ok()
        || cfg!(target_os = "macos")
        || cfg!(target_os = "windows");

    if is_ssh {
        #[cfg(feature = "tui-backend")]
        return "tui";
    }

    if has_display {
        #[cfg(feature = "egui-backend")]
        return "egui";
        #[cfg(all(not(feature = "egui-backend"), feature = "webview-backend"))]
        return "webview";
    }

    #[cfg(feature = "tui-backend")]
    return "tui";

    #[cfg(not(feature = "tui-backend"))]
    {
        #[cfg(feature = "egui-backend")]
        return "egui";
        #[cfg(all(not(feature = "egui-backend"), feature = "webview-backend"))]
        return "webview";
        #[cfg(not(any(feature = "egui-backend", feature = "webview-backend")))]
        {
            eprintln!("Error: no backend compiled");
            process::exit(1);
        }
    }
}

/// Read stdin and write to a temp file, returning its path.
fn read_stdin_to_tmpfile() -> PathBuf {
    let mut content = String::new();
    io::stdin().lock().read_to_string(&mut content).unwrap_or_else(|e| {
        eprintln!("Error: failed to read from stdin: {}", e);
        process::exit(1);
    });
    let tmp_dir = std::env::temp_dir().join("mdr");
    std::fs::create_dir_all(&tmp_dir).unwrap_or_else(|e| {
        eprintln!("Error: failed to create temp directory: {}", e);
        process::exit(1);
    });
    let tmp_file = tmp_dir.join(format!("stdin-{}.md", process::id()));
    std::fs::write(&tmp_file, &content).unwrap_or_else(|e| {
        eprintln!("Error: failed to write temp file: {}", e);
        process::exit(1);
    });
    tmp_file
}

/// egui and tui render a single file and have no drop target: `--new` is
/// webview-only, so tell the user rather than opening a useless window.
#[cfg(any(feature = "egui-backend", feature = "tui-backend"))]
fn require_file(file: Option<PathBuf>) -> PathBuf {
    file.unwrap_or_else(|| {
        eprintln!("Error: this backend needs a file; --new (empty window) is webview-only");
        eprintln!("Try: mdr --new --backend webview");
        process::exit(1);
    })
}

fn main() {
    // macOS can append a `-psn_0_12345` process-serial-number argument when the
    // app is launched by LaunchServices (Finder, AppleScript). clap would reject
    // it as unknown, so drop it before parsing.
    let args = std::env::args_os()
        .filter(|a| !a.to_string_lossy().starts_with("-psn_"));
    let cli = Cli::parse_from(args);

    if cli.list_backends {
        print_backends();
        process::exit(0);
    }

    #[cfg(unix)]
    if cli.install_cli {
        install_cli(cli.prefix.clone());
    }
    #[cfg(not(unix))]
    if cli.install_cli {
        eprintln!("Error: --install-cli is Unix-only; add the app directory to PATH instead");
        process::exit(1);
    }

    if cli.init {
        let path = cli.config.clone().unwrap_or_else(core::config::default_path);
        match core::config::write_default(&path) {
            Ok(()) => {
                eprintln!("Created config file: {}", path.display());
                process::exit(0);
            }
            Err(e) => {
                eprintln!("Error: {}", e);
                process::exit(1);
            }
        }
    }

    // Load config (explicit path errors if missing; default path is optional)
    let cfg_path = cli.config.clone().unwrap_or_else(core::config::default_path);
    let cfg = if cli.config.is_some() && !cfg_path.exists() {
        eprintln!("Error: config file '{}' not found", cfg_path.display());
        process::exit(1);
    } else {
        core::config::load(&cfg_path).unwrap_or_else(|e| {
            eprintln!("mdr: config error ({}): {}", cfg_path.display(), e);
            core::config::Config::default()
        })
    };

    core::set_verbose(cli.verbose || cfg.verbose.unwrap_or(false));
    core::urlpolicy::set_remote_images(!cli.no_remote_images && cfg.remote_images.unwrap_or(true));
    core::urlpolicy::set_allow_local_http(!cli.no_local_http && cfg.allow_local_http.unwrap_or(true));

    // iOS/Android apps are launched without a usable command line or stdin:
    // open the document bundled next to the executable (see scripts/ios-sim.sh),
    // or the path given in MDR_FILE.
    #[cfg(any(target_os = "ios", target_os = "android"))]
    let cli_file = cli.file.clone().or_else(|| {
        std::env::var_os("MDR_FILE").map(PathBuf::from).or_else(|| {
            std::env::current_exe()
                .ok()
                .and_then(|exe| exe.parent().map(|d| d.join("document.md")))
        })
    });
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    let cli_file = cli.file.clone();

    // `None` = start with the empty drop window (webview only).
    let file: Option<PathBuf> = match cli_file {
        Some(f) if f.as_os_str() == "-" => Some(read_stdin_to_tmpfile()),
        Some(f) => {
            if !f.exists() {
                eprintln!("Error: file '{}' not found", f.display());
                process::exit(1);
            }
            Some(f)
        }
        None if cli.new || launched_from_app_bundle() => None,
        None => {
            if io::stdin().is_terminal() {
                eprintln!("Error: missing required argument <FILE>");
                eprintln!("Usage: mdr <FILE> [OPTIONS]");
                eprintln!("       cat file.md | mdr [OPTIONS]");
                eprintln!("       mdr --new            (empty window, drop a file onto it)");
                eprintln!("Try 'mdr --help' for more information.");
                process::exit(1);
            }
            Some(read_stdin_to_tmpfile())
        }
    };

    #[cfg(feature = "webview-backend")]
    let view_opts = backend::webview::ViewOptions {
        editor: cli.edit || cfg.mode.as_deref() == Some("editor"),
        toc: cli.toc || cfg.toc.unwrap_or(false),
        lang: cli.lang.clone().or(cfg.lang.clone()),
    };

    let backend_str = cli.backend
        .or(cfg.backend)
        .unwrap_or_else(|| "auto".to_string());
    let backend = if backend_str == "auto" {
        detect_backend()
    } else {
        backend_str.as_str()
    };

    let result = match backend {
        #[cfg(feature = "egui-backend")]
        "egui" => backend::egui::run(require_file(file)),

        #[cfg(not(feature = "egui-backend"))]
        "egui" => {
            eprintln!("Error: egui backend not compiled. Rebuild with --features egui-backend");
            process::exit(1);
        }

        #[cfg(feature = "webview-backend")]
        "webview" => backend::webview::run(file, view_opts),

        #[cfg(not(feature = "webview-backend"))]
        "webview" => {
            eprintln!("Error: webview backend not compiled. Rebuild with --features webview-backend");
            process::exit(1);
        }

        #[cfg(feature = "tui-backend")]
        "tui" => backend::tui::run(require_file(file)),

        #[cfg(not(feature = "tui-backend"))]
        "tui" => {
            eprintln!("Error: tui backend not compiled. Rebuild with --features tui-backend");
            process::exit(1);
        }

        _ => unreachable!(),
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        process::exit(1);
    }
}
