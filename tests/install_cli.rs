//! `--install-cli` symlinks the executable inside `Mdr.app` into a bin
//! directory, so the app in the Dock and `mdr` in a terminal are one build.
//!
//! The rule that matters is the refusal: it replaces a symlink it (or a
//! previous install) made, but never a real file. Clobbering there would
//! destroy a Homebrew or `cargo install` binary of the same name, which is
//! exactly the kind of damage a user cannot undo from the error message.
#![cfg(unix)]

use std::process::Command;

fn mdr_bin() -> std::path::PathBuf {
    let mut path = std::env::current_exe().unwrap();
    path.pop(); // remove test binary name
    path.pop(); // remove "deps"
    path.push("mdr");
    path
}

/// A private prefix per test: these run in parallel and all write `<dir>/mdr`.
fn temp_prefix(label: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("mdr_test_install_{}_{}", label, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn install_into(dir: &std::path::Path) -> std::process::Output {
    Command::new(mdr_bin())
        .args(["--install-cli", "--prefix"])
        .arg(dir)
        .output()
        .expect("failed to run mdr")
}

#[test]
fn install_cli_creates_a_symlink_to_this_executable() {
    let dir = temp_prefix("creates");
    let out = install_into(&dir);
    assert!(
        out.status.success(),
        "--install-cli should succeed into a fresh directory: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let link = dir.join("mdr");
    let meta = std::fs::symlink_metadata(&link).expect("mdr should have been created");
    assert!(meta.file_type().is_symlink(), "it must be a symlink, so app updates follow automatically");
    assert_eq!(
        std::fs::read_link(&link).unwrap(),
        mdr_bin().canonicalize().unwrap_or_else(|_| mdr_bin()),
        "the link should point at the executable that installed it"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn install_cli_creates_the_prefix_directory() {
    // ~/.local/bin often does not exist yet on a fresh machine.
    let dir = temp_prefix("mkdir").join("nested").join("bin");
    let out = install_into(&dir);
    assert!(out.status.success(), "--install-cli should create its prefix directory");
    assert!(dir.join("mdr").exists());

    let _ = std::fs::remove_dir_all(dir.parent().unwrap().parent().unwrap());
}

#[test]
fn install_cli_replaces_a_symlink_it_already_made() {
    // Re-running after an app update has to be a no-op, not an error.
    let dir = temp_prefix("relink");
    assert!(install_into(&dir).status.success());
    let out = install_into(&dir);
    assert!(
        out.status.success(),
        "a second --install-cli should replace its own link: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(std::fs::symlink_metadata(dir.join("mdr")).unwrap().file_type().is_symlink());

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn install_cli_refuses_to_clobber_a_real_binary() {
    // The Homebrew / `cargo install` case. Overwriting here would delete
    // someone else's binary, so it must fail and say what to do instead.
    let dir = temp_prefix("clobber");
    let link = dir.join("mdr");
    std::fs::write(&link, "#!/bin/sh\necho not mdr\n").unwrap();

    let out = install_into(&dir);
    assert!(!out.status.success(), "--install-cli must not overwrite a real file");

    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("not a symlink"),
        "the error should say why it refused, got: {}",
        stderr
    );
    assert!(
        stderr.contains("--prefix"),
        "the error should offer a way forward, got: {}",
        stderr
    );
    assert_eq!(
        std::fs::read_to_string(&link).unwrap(),
        "#!/bin/sh\necho not mdr\n",
        "the existing binary must be left exactly as it was"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn install_cli_refuses_to_clobber_a_real_directory() {
    let dir = temp_prefix("clobberdir");
    std::fs::create_dir_all(dir.join("mdr")).unwrap();

    let out = install_into(&dir);
    assert!(!out.status.success(), "--install-cli must not overwrite a directory named mdr");
    assert!(dir.join("mdr").is_dir(), "the directory must survive");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn install_cli_reports_whether_the_prefix_is_on_path() {
    // The last line of output is the only instruction most users will read.
    let dir = temp_prefix("path");
    let out = install_into(&dir);
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("is not on PATH") || stdout.contains("is on PATH"),
        "it should say whether the prefix is usable, got: {}",
        stdout
    );

    let _ = std::fs::remove_dir_all(&dir);
}
