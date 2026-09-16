# mdr — mobile test handoff (iOS, macOS, and one Android build)

**For:** a Claude Code session on macOS, starting cold. This file is
self-contained; you are not expected to have seen this project before.

**Background:** suzuki.taka maintains `oxgenet/mdr`, a Rust Markdown reader for
mac/win/iOS/Android, and asked for tests on iOS and Android with a view to
selling the app cheaply on both stores. The Android half was built on a Windows
machine. You are picking up everything that needs a Mac — plus one Android
build that the Windows machine physically cannot produce.

**Read §4 first.** Task A blocks another person; the rest can follow.

---

## 1. Get the code

The work is on the **`mobile-tests`** branch, not on `main`:

```bash
git clone https://github.com/oxgenet/mdr.git
cd mdr
git checkout mobile-tests
git log --oneline -1     # 2f6e1de "Add Android shell and mobile contract tests..."
```

If you see `833b84a Release 0.4.1` instead, you are still on `main` and none of
this work is present — no `android/`, no `src/jni_bridge.rs`.

Commit your fixes onto this branch. It is not merged to `main` and should not
be until §9 has been reviewed and Task A has made the Rust actually compile.

## 2. Prerequisites

```bash
xcode-select --install
brew install xcodegen
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim \
                  aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk
```

Android NDK **28.2.13676358** (matching `android/app/build.gradle.kts`), via
Android Studio or:

```bash
sdkmanager 'ndk;28.2.13676358'
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
```

Python 3 is needed for Task B.

## 3. How the project is put together

One rendering implementation, three bindings over it:

```
core::page::render_page()          <- the single implementation
  |- src/ffi.rs          C ABI     -> ios/MdrApp (MdrCore.swift), macOS
  |- src/jni_bridge.rs   JNI       -> android/app (MdrCore.kt)
  \- src/backend/webview.rs        -> the desktop binary
```

That is what makes cross-platform testing cheap: **prove the core once in Rust,
then prove each binding carries it faithfully.** Do not re-assert Markdown
semantics in Swift — assert that the bridge did not mangle, drop or swap
anything.

**Pairing rule:** the unit tests in `src/ffi.rs`, the Android tests in
`android/app/src/androidTest/.../MdrCoreInstrumentedTest.kt`, and the iOS suite
you are about to write assert the *same contract*, test name for test name.
Change one, change all three.

### State of play

| Area | State |
|---|---|
| `src/ffi.rs` | 16 tests written — **never compiled** |
| `src/jni_bridge.rs` | New JNI mirror of the C ABI — **never compiled**; highest-risk file here |
| `src/core/page.rs` | New shared `render_page()`; `ffi.rs` is now a thin wrapper over it |
| `android/` | Complete. 30 tests written; 24 execute, 6 pass, 18 blocked on the missing `.so` |
| `.github/workflows/ci.yml` | New `android` + `android-instrumented` jobs; mobile-core test step on all three OSes |
| `ios/MdrApp` | Untouched — and has **no XCTest target at all** |

Why none of the Rust was compiled: the Windows machine has Smart App Control
enforced, which refuses every unsigned executable Cargo launches
(`os error 4551`). It is irreversible to disable, so it was left alone.

---

## 4. Task A — make Rust compile, and ship two `.so` files back

Everything on the Windows side is stalled behind this.

```bash
cargo test                                             # full suite
cargo test --lib --no-default-features --features svg  # the mobile core
cargo clippy --all-targets -- -D warnings
```

**Expect compile errors.** `src/ffi.rs`, `src/core/page.rs` and especially
`src/jni_bridge.rs` were written without a compiler. One error was already
found and fixed by reading the crate source: `jni` 0.21 has no
`JObject::is_null`, so the null check goes through `as_raw().is_null()`.
Already confirmed against jni 0.21.1 sources, so do not "fix" these:

- `get_string(&mut self, obj: &JString)` — takes `&mut self`
- `new_string(&self, from: S)` — takes `&self`
- `impl From<JavaStr> for String` exists, so `.map(Into::into)` is valid
- `JString::into_raw() -> jstring`, and `jstring` is an alias of `jobject`

Then build the Android core:

```bash
cargo check --target aarch64-linux-android --lib --no-default-features --features svg

cargo ndk -t arm64-v8a -t x86_64 -o android/app/src/main/jniLibs \
    build --release --lib --no-default-features --features svg

file android/app/src/main/jniLibs/x86_64/libmdr.so   # ELF 64-bit LSB shared object
```

**Send back to Dhruv:**

1. `android/app/src/main/jniLibs/x86_64/libmdr.so` — the emulator needs this one
2. `android/app/src/main/jniLibs/arm64-v8a/libmdr.so` — for real phones
3. The corrected `src/jni_bridge.rs`, `src/ffi.rs`, `src/core/page.rs`, committed

`jniLibs/` is gitignored, so the binaries have to travel out of band.

Windows then runs `android/run-device-tests.ps1` and drives the remaining 18
Android tests green.

## 5. Task B — regenerate the licence table, or CI fails for everyone

`comrak`'s `syntect` feature was removed (§10). `src/core/licenses.rs` is
generated from the dependency graph and checked by CI. Windows has no Python,
so this is yours:

```bash
python scripts/gen-licenses.py
python scripts/gen-licenses.py --check   # must exit 0
cargo test --lib                          # page.rs asserts CRATES.len() > 100
```

## 6. Task C — add an XCTest unit target over `MdrCore`

Mirror `android/app/src/androidTest/.../MdrCoreInstrumentedTest.kt` case for
case. Add the target to `ios/MdrApp/project.yml` so `xcodegen generate`
produces it.

Assertions to port:

- the library loads and `MdrCore.version` equals the bundle's version string
- `renderPage` view flags produce `<body class="no-toc">` / `"no-toc editing"` /
  `""` / `"editing"` for the four `(editor, toc)` combinations
- source is HTML-escaped into the `<textarea>`, while raw HTML still renders in
  the body (comrak runs with `render.unsafe = true` deliberately)
- headings produce `<li class="toc-h1"><a href="#slug">` **and** a matching
  `<h1 id="slug">` — `DocumentViewController.showToc()` depends on both
- language order: content detection (`ja` / `ko` / `zh-Hans`), explicit beats
  detection, front matter beats explicit, `"auto"` means none, an unparseable
  tag falls back to detection
- `updateScript` output contains no newline and JSON-escapes quotes and
  backslashes — it is fed to `evaluateJavaScript`, so a raw quote is a syntax
  error, not a failed update
- relative images inline as `data:image/png;base64,` from a real `baseDir`;
  `../` outside it does **not** inline; an empty `baseDir` still renders
- empty input and a ~200k-character document both return a complete page

Do not assert a language tag for empty or Latin-only documents: resolution
falls back to the OS locale, so those assertions pass in CI and fail on a
Japanese machine. This already bit the project once (CHANGELOG 0.4.0).

`MdrCore.take()` frees every returned pointer, so a leak or double-free shows
up here first. Worth one run under the Address Sanitizer.

## 7. Task D — replace the grep assertions in `ios/build-app.sh`

Today it boots a simulator and `grep`s `[mdr-ios] opened` / `rendered` out of
NSLog. Turn that into an XCUITest driven by `xcodebuild test`, so failures come
back structured instead of as a missing log line. Cover: open from the document
browser, edit with live preview, in-place autosave, the TOC sheet, the search
bar's match count, share as `.md` and PDF.

Keep the script's simulator setup — it works, and `MDR_EXPECT_LANG` is worth
keeping.

One failure mode found on Android that is worth checking on iOS: loading the
native core inside a class initialiser took down the whole process when the
library was missing, aborting the rest of the test run. Make sure a missing or
mismatched `libmdr.a` surfaces as a readable failure.

## 8. Task E — macOS

`ci.yml`'s `macos-app` job builds `Mdr.app` and checks the bundle, but nothing
tests behaviour. LEARNINGS.md:21 notes AppleScript drives the app well
(`open -a Mdr file.md`, then read `name of first window`). Worth automating:
document switching, relative-link navigation between `.md` files, and
`--install-cli`'s refusal to clobber a real binary.

## 9. Decisions taken on the Windows/Android side — please review

**`comrak`'s `syntect` feature was removed** (`Cargo.toml`). Nothing in the
crate references `comrak::plugins::syntect`: the webview highlights with
bundled highlight.js, and the egui backend brings its own syntect through
`egui_commonmark`. It was pulling in `onig_sys`, a C library, which made a C
toolchain a build prerequisite for the iOS staticlib and the Android cdylib.
`cargo tree` confirms both crates left the graph; the `Cargo.lock` diff is
exactly those two, 24 lines. **If upstream wants the feature, revert it and
accept the C dependency.**

**`crate-type` gained `cdylib`** for Android's `System.loadLibrary`. Every
`cargo build` now also links a dynamic library. If that shows up in CI times,
restrict it per-target rather than dropping it.

**The CI mobile jobs were guarding the wrong build.** They compiled
`--no-default-features --features webview-backend`, while `ios/build-app.sh`
links `--lib --no-default-features --features svg`. The configuration that
actually ships was unguarded. Fixed, with the webview build kept as a labelled
secondary probe.

**`Cargo.lock` is tracked**, contrary to what LEARNINGS.md:31 used to say
(now corrected there).

## 10. Gotchas worth knowing before you start

Read `LEARNINGS.md` — it is the project's accumulated memory, in Japanese.
Lines 16, 17, 21, 23 and 40 will save real time. The essentials:

- iOS staticlib needs `CARGO_PROFILE_RELEASE_LTO=off` and
  `RUSTFLAGS="-C embed-bitcode=no"` — Xcode's linker cannot read the bitcode a
  newer rustc emits
- simulator builds are arm64-only: `EXCLUDED_ARCHS[sdk=iphonesimulator*]=x86_64`
- XcodeGen's `entitlements: path:` silently blanks the file unless
  `properties:` is also given
- App Groups need a signed build, so the Share Extension cannot be verified on
  an unsigned simulator build
- `open -a Mdr file.md` is enough to open a document; Finder and `open -a`
  cannot carry CLI flags at all (they pass an Apple Event), so only
  `~/.config/mdr/config.kdl` can change Finder-launched behaviour

## 11. Definition of done

- [ ] `cargo test` and `cargo test --lib --no-default-features --features svg` pass
- [ ] `cargo check --target aarch64-linux-android --lib --no-default-features --features svg` passes
- [ ] Both `libmdr.so` files sent to Dhruv, and the Rust fixes committed
- [ ] `python scripts/gen-licenses.py --check` exits 0
- [ ] An XCTest target exists, mirrors `MdrCoreInstrumentedTest.kt`, and passes
- [ ] `ios/build-app.sh` fails loudly on a real regression, not just a missing log line
- [ ] CI runs the iOS tests on a macOS runner
