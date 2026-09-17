//! mdr — Markdown viewer/editor core.
//!
//! The library exposes the rendering core (`core`), the desktop backends
//! (`backend`, feature-gated) and two native-shell bindings over the same
//! rendering entry points: a C ABI (`ffi`) that the iOS shell links, and a JNI
//! bridge (`jni_bridge`) that the Android shell loads as `libmdr.so`.

pub mod backend;
pub mod core;
#[cfg(feature = "svg")]
pub mod ffi;
#[cfg(all(target_os = "android", feature = "svg"))]
pub mod jni_bridge;
