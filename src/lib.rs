//! mdr — Markdown viewer/editor core.
//!
//! The library exposes the rendering core (`core`), the desktop backends
//! (`backend`, feature-gated) and a C ABI (`ffi`) used by the iOS/Android shells.

pub mod backend;
pub mod core;
#[cfg(feature = "svg")]
pub mod ffi;
