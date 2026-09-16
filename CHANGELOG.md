# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-09-16

### Added
- **About dialog** in the `⋮` menu: version, copyright, and the licence of
  every third-party component (404 crates plus the two bundled JS assets).
  The list is generated from `cargo metadata` by `scripts/gen-licenses.py`
  into `src/core/licenses.rs`, and CI fails when it drifts from the
  dependency graph
- Developer ID signing and notarization for `Mdr.app`, off unless the
  `MACOS_SIGN_IDENTITY` / `MACOS_NOTARY_PROFILE` variables (repository
  secrets in CI) are set; the ad-hoc path is unchanged without them
- `macos/setup-signing.sh` reports what a notarized build still needs and
  prints the portal steps, the build command and the CI secret values

### Changed
- The fork is now attributed to **Opusify IT Solutions Pvt. Ltd.**
  (previously oxge.net) in LICENSE, NOTICE.md, Cargo.toml, the Windows
  resource and every packaging manifest. Clever Cloud's notice is
  unchanged — MIT requires it to travel with every copy
- WinGet package identifier is now `opusify.mdr` (was `oxgenet.mdr`);
  nothing was published under the old name. The Homebrew tap, Scoop
  bucket and AUR package keep their `oxgenet` names, which belong to the
  GitHub organisation hosting them

### Fixed
- Documented that a Homebrew Cask is **not** viable while the app is only
  ad-hoc signed: Cask applies quarantine rather than removing it,
  `--no-quarantine` was removed in Homebrew 4.7, and casks failing
  Gatekeeper lost support on 2026-09-01 (Homebrew/brew#20755). A ready
  cask waits in `packaging/homebrew/mdr-app.rb` for the notarized build

## [0.4.0] - 2026-09-15 (oxgenet fork)

First release of the oxgenet fork of mdr (https://github.com/oxgenet/mdr),
forked from Clever Cloud's v0.3.2. Copyright (c) 2026 Opusify IT Solutions Pvt. Ltd. for
the modifications; original work (c) 2026 Clever Cloud, MIT.

### Added
- Webview **viewer mode** by default (no sidebar/toolbar) with a `⋮` menu to
  switch to **editor mode** (source + live preview, Cmd/Ctrl+S save) and toggle
  the table of contents; `--edit`, `--toc` flags and `mode`/`toc` config keys
- **CJK-aware rendering**: language resolution (front matter `lang:`, `--lang`,
  config `lang`, content detection, OS locale) sets `<html lang>`; `:lang()`
  font stacks for ja / zh-Hans / zh-Hant / ko for body, code, editor, Mermaid
- Leading YAML front matter is stripped from the rendered document
- CI: dependency refresh builds (macOS arm64/x64, Windows x64/arm64), Windows
  rendering screenshots, experimental iOS/Android compile checks
- `LICENSE`, `NOTICE.md`, packaging templates under `packaging/`
- Remote image policy: https always, plain http only for localhost / private
  IP literals / `*.local` on common ports; blocked or failed images become
  placeholders. `--no-remote-images`, `--no-local-http`, config keys
- iOS document-based app (`ios/MdrApp`) and Share Extension; Windows CI screenshots
- **macOS app bundle `Mdr.app`** (`macos/build-app.sh`): universal arm64+x86_64,
  icon from `assets/logo-appicon.svg`, ad-hoc signed, declares the Markdown
  document types so Finder can open files into it. Released as
  `Mdr-X.Y.Z-macos-universal.dmg` / `.zip`; downloads need
  `xattr -dr com.apple.quarantine` (not notarized)
- **Empty window with drag & drop**: launching without a file (Finder/Dock, or
  `mdr --new`) opens a drop target instead of failing. Dropping a Markdown file
  — or a later one — replaces the displayed document
- **Relative Markdown links** (`[x](./sub/b.md)`, `../a.md`) open in the same
  window, resolved against the currently open document's directory
- `mdr --install-cli` symlinks the executable as `mdr` into `~/.local/bin`
  (`--prefix` for elsewhere), so the copy inside Mdr.app is reachable from a
  terminal without sudo or a hand-written symlink

### Changed
- Default Cargo features are now `webview-backend` only (egui/tui opt-in)
- The webview backend now holds the open document (path, base directory,
  watcher) as swappable state rather than binding it once at startup. Image
  paths and live-preview updates therefore resolve against the **current**
  document's directory, which is what makes document switching correct

### Fixed
- `-psn_0_*`, which LaunchServices can append to argv when an app is launched
  from Finder, no longer makes argument parsing fail
- `ffi::null_inputs_do_not_crash` no longer depends on the host's locale (an
  empty document falls back to the OS language for `<html lang>`)
- Package identity moved to the oxgenet namespace (Homebrew `oxgenet/tap/mdr`,
  Scoop bucket `oxgenet`, WinGet `oxgenet.mdr`); not published to crates.io

## [0.3.2] - 2026-06-22

### Added
- TOC panel in egui is now **resizable** by dragging its edge (#27)
- HTTP image fetching in TUI now has a **30-second timeout**
- `file_to_data_uri()` now rejects image files larger than **100 MB** to prevent OOM

### Fixed
- Replaced `std::mem::forget` with explicit `Box::leak` in `watcher.rs` (#16)
- Mermaid diamond-node panic reported upstream; workaround already in place (#4)
- `cargo binstall mdr` confirmed working (#22)

## [0.3.1] - 2026-06-22

### Added
- TOC toggle in egui backend: press **F10** or click *Hide TOC / Show TOC* in the search bar (#32, #41)
- Window size and position persistence in egui backend via eframe's `persistence` feature (#43)
- System font loading in egui backend for non-Latin script support (CJK, etc.) (#31)
- Image file validation by magic bytes across all backends — invalid/mislabeled images render a visible placeholder instead of failing silently (#14)

### Fixed
- Headings inside fenced code blocks are no longer treated as section boundaries in egui (#30)

### Changed
- Cargo dependencies bumped:
  - `eframe` 0.33 → 0.34
  - `egui_commonmark` 0.22 → 0.23
  - `ratatui` 0.29 → 0.30
  - `ratatui-image` 4.2 → 11.0

## [0.3.0] - 2026-05-20

### Added
- Highlight.js syntax highlighting for code blocks in the webview backend, with `prefers-color-scheme` GitHub light/dark themes embedded via `include_str!`. Injected only when fenced code blocks are present (#35) — thanks @njreid
- Custom KDL v2 grammar definition for highlight.js (#35)
- Fullscreen expand overlay for images and Mermaid diagrams in the webview backend, with hover button, double-click, and `Esc` to close (#34) — thanks @njreid
- User config file at `~/.config/mdr/config.kdl` (KDL v2) with `--init` to scaffold and `--config PATH` to override (#36) — thanks @njreid
- `system-ui` added to the default font stack for a native desktop look (#36) — thanks @njreid
- `with_devtools(true)` on the webview to enable in-app dev tools (#34)

### Fixed
- Webview backend crash on Linux/Wayland (`the window handle kind is not supported`). Switch to wry's GTK-native API (`WebViewBuilderExtUnix::build_gtk`) on Linux so the same binary works on X11 and Wayland (#33, closes #28) — thanks @njreid
- TUI backend now exits early when stdout is not a terminal. Without this, `enable_raw_mode()` succeeds on Windows pipes and the event loop spins forever — this was the cause of every `main` CI run being cancelled at the 6h timeout since February (#39)

### Changed
- Cargo dependencies bumped — major versions where drop-in (#40):
  - `comrak` 0.50 → 0.52
  - `mermaid-rs-renderer` 0.1 → 0.2
  - `resvg`, `usvg` 0.45 → 0.47
  - `tiny-skia` 0.11 → 0.12
  - `wry` 0.54 → 0.55
  - `tao` 0.34 → 0.35
  - `muda` 0.15 → 0.19
  - `ratatui-image` 4.1 → 4.2

### Internal
- `timeout-minutes: 90` added on the CI check job so a future regression of the kind that caused the 6-month outage fails fast

## [0.2.6] - 2026-02-23

### Added
- Application window icon: both egui and webview backends now display the mdr logo as window icon

## [0.2.4] - 2026-02-23

### Added
- `--list-backends` flag to display available backends at runtime
- Backend names shown in CLI help output

## [0.2.3] - 2026-02-22

### Fixed
- Homebrew tap release workflow: remove broken copy action, fix heredoc syntax

## [0.2.2] - 2026-02-22

### Security
- Path traversal protection for local file access
- Content Security Policy (CSP) headers in webview backend
- Regex caching to prevent ReDoS
- HTML encoding of user-controlled content (`html_encode`)

## [0.2.1] - 2026-02-22

### Fixed
- Windows build: move `[target.'cfg(unix)'.dependencies]` section after optional deps in `Cargo.toml`

## [0.2.0] - 2026-02-22

### Added
- Mouse scroll support in TUI backend
- Mermaid diagram rendering as terminal images in TUI backend
- SVG image support in TUI backend
- Offline Mermaid rendering via embedded `mermaid.js`
- Project logo in README and documentation
- Verbose mode (`-v`) for debug output across all backends

### Fixed
- Image rendering consistency across egui, webview, and TUI backends
- Local image path resolution in TUI backend
- SVG images not displaying in webview backend (#10)
- SVG rendering in egui: rasterize to PNG instead of inline embedding (security fix)
- Mermaid rendering improvements in TUI and webview backends

### Changed
- SVG images rasterized to PNG in egui backend for consistency
- README updated with logo and LLM-era motivation section

## [0.1.1] - 2026-02-22

### Added
- WinGet package publishing job in release workflow
- AUR (Arch User Repository) package publishing job in release workflow
- crates.io publish job in release workflow

## [0.1.0] - 2026-02-22

### Added
- In-document search (`/` to open, `n`/`N` to navigate matches)
- Packaging support: Homebrew, Nix, pre-built binaries
- Release infrastructure: GitHub Actions CI/CD pipeline

## [0.9] - 2026-02-22

### Added
- Initial project bootstrap with egui and webview dual rendering backends
- TUI backend using Ratatui for terminal rendering
- TOC (Table of Contents) sidebar navigation
- Mermaid diagram rendering support
- Image rendering in TUI backend with local image path resolution
- Auto-detection of rendering backend based on environment
- Security hardening for file access and rendering pipeline
- GitHub Actions CI/CD workflow
- 58 unit tests

### Fixed
- Mermaid diagram text rendering
- TOC scroll navigation in egui backend
- Mermaid rendering robustness in egui backend

[0.3.2]: https://github.com/CleverCloud/mdr/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/CleverCloud/mdr/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/CleverCloud/mdr/compare/v0.2.8...v0.3.0
[0.2.6]: https://github.com/CleverCloud/mdr/compare/v0.2.5...v0.2.6
[0.2.4]: https://github.com/CleverCloud/mdr/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/CleverCloud/mdr/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/CleverCloud/mdr/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/CleverCloud/mdr/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/CleverCloud/mdr/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/CleverCloud/mdr/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/CleverCloud/mdr/compare/0.9...v0.1.0
[0.9]: https://github.com/CleverCloud/mdr/releases/tag/0.9
