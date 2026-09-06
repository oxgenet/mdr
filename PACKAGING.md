# Packaging & distribution (oxgenet fork)

This fork keeps the binary name `mdr` but publishes under **oxgenet-namespaced
package identifiers** so it never collides with the original Clever Cloud
packages. Everything here assumes a Git tag `vX.Y.Z` on `main`; the release
workflow builds, publishes the GitHub Release, and updates the channels that
are enabled.

## Identity (use these strings everywhere)

| Field | Value |
|---|---|
| Project name | mdr (oxgenet fork) |
| Binary | `mdr` |
| Repository | https://github.com/oxgenet/mdr |
| Maintainer | tkykszk@gmail.com |
| License | MIT — `LICENSE` carries both copyright lines (Clever Cloud + tkykszk@gmail.com) |
| Attribution | `NOTICE.md` (fork of https://github.com/CleverCloud/mdr, not affiliated) |
| Homebrew | `oxgenet/tap/mdr` (tap repo `oxgenet/homebrew-tap`) |
| Scoop | bucket `oxgenet` (repo `oxgenet/scoop-bucket`), app `mdr` |
| WinGet | `oxgenet.mdr` |
| AUR | `mdr-ox-bin` |
| Debian / RPM | package `mdr`, from GitHub Release assets |

Every package must ship `LICENSE` and either `NOTICE.md` or an equivalent
"fork of Clever Cloud's mdr" statement (MIT requires the copyright and
permission notice to travel with the software). The templates in `packaging/`
already do this.

## Release assets produced by CI (`v*` tag)

| Asset | Target |
|---|---|
| `mdr-aarch64-apple-darwin.tar.gz` | macOS Apple Silicon |
| `mdr-x86_64-apple-darwin.tar.gz` | macOS Intel |
| `mdr-x86_64-pc-windows-msvc.zip` | Windows x64 |
| `mdr-aarch64-pc-windows-msvc.zip` | Windows ARM64 |
| `mdr-x86_64-unknown-linux-gnu.tar.gz` | Linux x64 (needs libwebkit2gtk-4.1, libgtk-3) |
| `mdr_X.Y.Z_amd64.deb` / `mdr-X.Y.Z-1.x86_64.rpm` | Debian/Ubuntu, Fedora/RHEL |

Each archive contains `mdr` (or `mdr.exe`), `LICENSE`, and `NOTICE.md`.

## Channels

### Homebrew (macOS, Linux)

1. Create the tap repository **`oxgenet/homebrew-tap`** with `Formula/mdr.rb`
   (start from `packaging/homebrew/mdr.rb`).
2. Repo settings of `oxgenet/mdr`: secret `HOMEBREW_TAP_TOKEN` = fine-grained
   PAT with *Contents: read/write* on `oxgenet/homebrew-tap`; variable
   `HOMEBREW_TAP_ENABLED=true`.
3. Users: `brew install oxgenet/tap/mdr`. The formula declares
   `conflicts_with "mdr"`, so the upstream formula must be uninstalled first.

### Scoop (Windows)

1. Create **`oxgenet/scoop-bucket`** with `bucket/mdr.json`
   (start from `packaging/scoop/mdr.json`).
2. Secret `SCOOP_BUCKET_TOKEN` (PAT with write on the bucket repo); variable
   `SCOOP_ENABLED=true`.
3. Users:
   ```
   scoop bucket add oxgenet https://github.com/oxgenet/scoop-bucket
   scoop install oxgenet/mdr
   ```

### WinGet (Windows)

1. Secret `WINGET_TOKEN` (classic PAT, `public_repo`); variable `WINGET_ENABLED=true`.
2. The first version must be submitted as a new package PR to
   `microsoft/winget-pkgs` under `manifests/o/oxgenet/mdr/`; see
   `packaging/winget/oxgenet.mdr.yaml` for the three manifests. Review takes days.
3. Users: `winget install oxgenet.mdr`.

### Debian / Ubuntu and Fedora / RHEL

`cargo deb` and `cargo generate-rpm` use the metadata in `Cargo.toml`
(`[package.metadata.deb]`, `[package.metadata.generate-rpm]`), which install
`/usr/bin/mdr`, `/usr/share/doc/mdr/copyright` (DEP-5, from
`packaging/debian/copyright`) and `NOTICE.md`. Runtime dependencies are
auto-detected. Users:

```
sudo apt install ./mdr_X.Y.Z_amd64.deb
sudo dnf install ./mdr-X.Y.Z-1.x86_64.rpm
```

An apt/yum repository on GitHub Pages can be added later; Release assets are
sufficient to start.

### AUR (optional)

Package name `mdr-ox-bin` (`provides=('mdr')`, `conflicts=('mdr' 'mdr-bin')`).
Secret `AUR_SSH_PRIVATE_KEY`; variable `AUR_ENABLED=true`.

### Not published

- **crates.io**: this fork is not published there; the `mdr` crate remains
  upstream's. `publish = false` is set in `Cargo.toml`.
- **Snap / Flatpak / Nix**: not maintained by the fork.

## Cutting a release

```bash
# 1. bump version in Cargo.toml and add a CHANGELOG entry
# 2. commit, then tag and push
git tag v0.4.0
git push origin main v0.4.0
```

The release workflow does the rest. If a channel job fails, the GitHub Release
itself is still created; rerun the failed job after fixing secrets.
