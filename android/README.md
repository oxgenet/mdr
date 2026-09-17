# mdr for Android

A Markdown reader that shares its entire rendering pipeline with the desktop
build and the iOS app. The Kotlin here is a shell: it opens a document, hands
the text to the Rust core, and puts the resulting page in a `WebView`.

```
MainActivity (Kotlin)
  └─ MdrCore.kt            JNI declarations
       └─ libmdr.so        src/jni_bridge.rs
            └─ core::page::render_page()   ← shared with iOS and desktop
```

`src/jni_bridge.rs` and `src/ffi.rs` (the C ABI iOS links) are two bindings over
one implementation, so a rendering change lands on every platform at once.

## Building

Prerequisites: JDK 17, the Android SDK with NDK 28.2.13676358, a Rust toolchain
with the Android targets, and `cargo-ndk`.

```bash
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk

cd android
./gradlew assembleDebug
```

`:app:buildRustCore` cross-compiles `libmdr.so` for `arm64-v8a` and `x86_64`
straight into `app/src/main/jniLibs/`, then the normal Android build picks it
up. The Rust feature set is `--no-default-features --features svg` — the
rendering core plus the shell bindings, and no desktop backend. It is the same
set `ios/build-app.sh` builds.

Pass `-PskipRustBuild` to reuse the `.so` files already in place, which keeps
Kotlin-only edits fast.

## Testing

| Suite | Command | Needs |
|---|---|---|
| JVM unit tests | `./gradlew :app:testDebugUnitTest` | nothing |
| Instrumented tests | `./gradlew :app:connectedDebugAndroidTest` | a device or emulator, and `libmdr.so` |

`run-device-tests.ps1` wraps the second row the way `ios/build-app.sh` wraps the
simulator: it boots an AVD if none is attached, runs the suite, prints a
per-class summary from the JUnit XML, and shuts the emulator down again.

```powershell
./run-device-tests.ps1
./run-device-tests.ps1 -TestClass net.oxge.mdr.MdrCoreInstrumentedTest
```

It warns up front when `libmdr.so` is missing, because without it every test
that touches the core fails with `UnsatisfiedLinkError` rather than telling you
what is actually wrong.

`app/src/test/` holds only pure Kotlin logic. Anything that touches the Rust
core lives in `app/src/androidTest/`, because `libmdr.so` needs a real Android
runtime to load.

`MdrCoreInstrumentedTest` deliberately mirrors the unit tests in `src/ffi.rs`.
The Rust tests prove the core is correct; these prove the JNI bridge carries it
faithfully — the library loads, strings survive the JVM boundary both ways,
booleans do not get swapped, and paths behave on an Android filesystem.
**If you change an assertion on one side, change it on the other.**

## Known limitations

- **Relative images usually do not resolve.** A `content://` URI from the
  Storage Access Framework names a document, not a directory, so there is no
  `baseDir` to resolve `![](pic.png)` against. Images that are already `data:`
  URIs, and documents opened from a `file://` URI, are unaffected. Fixing this
  properly means `ACTION_OPEN_DOCUMENT_TREE` and resolving siblings through
  `DocumentFile` — deliberately left out of the first version.
- **Viewer only.** There is no editor pane or save path yet; iOS has both. The
  page ships the editor UI, so wiring it up is mostly plumbing a save back
  through the content resolver.
- **No share extension.** iOS has one; the Android equivalent is the `SEND`
  intent filter in the manifest, which handles shared text but not yet
  shared files written back to storage.

## Developing on Windows

Two things bite on a Windows host, neither of which affects CI:

- **Smart App Control blocks Cargo.** Every build script Cargo compiles is a
  fresh unsigned executable, which an enforced policy refuses with
  `os error 4551`. `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy`
  reports the state. Turning it off cannot be undone without reinstalling
  Windows, so build the Rust core in WSL, on CI, or on another machine, and use
  `-PskipRustBuild` locally. The Gradle and Kotlin side is unaffected.
- **The GNU Rust host needs a `dlltool`.** rustup's bundled one has no
  assembler to call. The NDK's `llvm-dlltool.exe` accepts the same arguments —
  copy it somewhere on `PATH` as `dlltool.exe`.
