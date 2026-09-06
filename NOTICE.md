# NOTICE — provenance and attribution

This repository, **oxgenet/mdr**, is a fork of **mdr** by Clever Cloud.

| | |
|---|---|
| Original project | https://github.com/CleverCloud/mdr |
| Original author | Clever Cloud <opensource@clever-cloud.com> (initial commit by Quentin ADAM, 2026-02-22) |
| Original license | MIT — declared by the upstream project in `Cargo.toml` (`license = "MIT"`) and `README.md` ("## License: MIT"). Upstream ships no separate `LICENSE` file; the MIT text in this repository's `LICENSE` reproduces the standard MIT terms under which upstream published the work. |
| Fork point | upstream `main` at commit `26e9250` (release v0.3.2, 2026-06-22) |
| Fork maintainer | tkykszk@gmail.com |
| Fork repository | https://github.com/oxgenet/mdr |
| Fork license | MIT (same terms). Modifications are Copyright (c) 2026 tkykszk@gmail.com. |

## Relationship to the original

- This fork is **not affiliated with, endorsed by, or supported by Clever Cloud**.
  Do not report issues with this fork to the upstream project.
- The binary keeps the name `mdr` for command-line compatibility. All package
  identifiers are namespaced so they never collide with upstream packages:
  Homebrew `oxgenet/tap/mdr`, Scoop bucket `oxgenet`, WinGet `oxgenet.mdr`,
  AUR `mdr-ox-bin`.
- Upstream's own distribution channels (`CleverCloud/misc/mdr`, `CleverCloud.mdr`,
  `mdr-bin`, crates.io `mdr`) continue to ship the original, unmodified project.
  This fork is **not** published to crates.io.

## What this fork changes (summary)

- Webview backend opens in a chrome-less **viewer mode** by default; a `⋮` menu
  switches to an **editor mode** (source pane + live preview, save with Cmd/Ctrl+S)
  and toggles the table of contents. New `--edit`, `--toc` flags and config keys.
- **CJK-aware rendering**: document language resolution (front matter `lang:`,
  `--lang`, config, content detection, OS locale) sets `<html lang>` and
  `:lang()` font stacks for Japanese, Simplified/Traditional Chinese, Korean.
- Default Cargo features reduced to the webview backend.
- CI: dependency refresh + macOS/Windows builds, Windows rendering screenshots,
  experimental iOS/Android compile probes.

The full history is in `git log` and `CHANGELOG.md`.

## Redistribution requirements (for packagers)

When redistributing binaries or source of this fork, include:

1. The `LICENSE` file (both copyright lines and the MIT permission notice), and
2. this `NOTICE.md` or an equivalent statement that the software is a fork of
   Clever Cloud's mdr.

Ready-made templates that already satisfy this are in `packaging/`
(Homebrew formula, Scoop manifest, WinGet manifests, Debian `copyright`).

## Third-party components

mdr is built on Rust crates, each under its own license (MIT / Apache-2.0 /
MPL-2.0 etc.). Run `cargo license` or `cargo tree` in this repository for the
complete list. Bundled JavaScript assets: `mermaid.min.js` (MIT, Mermaid
contributors) and `highlight.min.js` (BSD-3-Clause, highlight.js contributors)
in `assets/`.
