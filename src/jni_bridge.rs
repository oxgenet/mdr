//! JNI entry points for the Android shell (`net.oxge.mdr.MdrCore`).
//!
//! The iOS shell reaches the rendering core through the plain C ABI in
//! [`crate::ffi`]; the JVM cannot call that directly, so this module exposes the
//! same four operations as JNI functions. Both sides delegate to
//! [`crate::core::page::render_page`] and [`crate::core::page::render_update_js`],
//! so there is one implementation and two bindings — not two implementations.
//!
//! Null and un-decodable Java strings are treated as empty, matching how
//! [`crate::ffi`] treats a null `*const c_char`. Returning a JNI string
//! transfers it to the JVM, so there is no counterpart to `mdr_free` here.
//!
//! The contract is asserted twice: in `ffi`'s unit tests (which run on any
//! host) and in `android/app/src/androidTest`, which loads the real
//! `libmdr.so` on a device or emulator.

#![allow(non_snake_case)]

use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jstring};
use jni::JNIEnv;
use std::path::Path;

use crate::core::page::{lang_tag, render_page, render_update_js};

/// A Java string as a Rust `String`; null or un-decodable becomes empty.
///
/// `jni` 0.21 has no `is_null` on `JObject`, so the null check goes through the
/// raw pointer. `get_string` would otherwise reject it and we would lose the
/// distinction between "null argument" and "conversion failed" — both of which
/// should behave the way the C ABI does and yield an empty string.
fn arg(env: &mut JNIEnv, s: &JString) -> String {
    if s.as_raw().is_null() {
        return String::new();
    }
    env.get_string(s).map(Into::into).unwrap_or_default()
}

/// Hand a Rust `String` to the JVM. Null on failure, which reaches Kotlin as a
/// null return rather than as a crash inside the render path.
fn out(env: &mut JNIEnv, s: String) -> jstring {
    env.new_string(s)
        .map(|j| j.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn opt(s: &str) -> Option<&str> {
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

/// Render a complete HTML page (viewer/editor UI included) for `markdown`.
/// `baseDir` resolves relative images; `lang` is an explicit tag or "" for auto.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeRenderPage<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    markdown: JString<'local>,
    base_dir: JString<'local>,
    lang: JString<'local>,
    editor: jboolean,
    toc: jboolean,
) -> jstring {
    let md = arg(&mut env, &markdown);
    let base = arg(&mut env, &base_dir);
    let lang = arg(&mut env, &lang);
    let html = render_page(&md, Path::new(&base), opt(&lang), editor != 0, toc != 0);
    out(&mut env, html)
}

/// JavaScript that updates an already loaded page (body, TOC, lang) in place.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeRenderUpdateJs<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    markdown: JString<'local>,
    base_dir: JString<'local>,
    lang: JString<'local>,
) -> jstring {
    let md = arg(&mut env, &markdown);
    let base = arg(&mut env, &base_dir);
    let lang = arg(&mut env, &lang);
    let js = render_update_js(&md, Path::new(&base), opt(&lang));
    out(&mut env, js)
}

/// Resolved BCP 47 language tag for the document ("" when none).
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeDetectLang<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    markdown: JString<'local>,
    lang: JString<'local>,
) -> jstring {
    let md = arg(&mut env, &markdown);
    let lang = arg(&mut env, &lang);
    let tag = lang_tag(&md, opt(&lang));
    out(&mut env, tag)
}

/// Allow or forbid loading images from http(s) URLs at all.
///
/// The policy is process-global in `core::urlpolicy`, which is why this is a
/// setter rather than a render argument. Android has no `config.kdl`, so the
/// settings screen drives it through here.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeSetRemoteImages<'local>(
    _env: JNIEnv<'local>,
    _class: JClass<'local>,
    on: jboolean,
) {
    crate::core::urlpolicy::set_remote_images(on != 0);
}

/// Allow or forbid plain-http images for local and private addresses.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeSetAllowLocalHttp<'local>(
    _env: JNIEnv<'local>,
    _class: JClass<'local>,
    on: jboolean,
) {
    crate::core::urlpolicy::set_allow_local_http(on != 0);
}

/// Current remote-image setting, so the shell can show the real state.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeRemoteImages<'local>(
    _env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jboolean {
    u8::from(crate::core::urlpolicy::remote_images())
}

/// Current plain-http-for-local-addresses setting.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeAllowLocalHttp<'local>(
    _env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jboolean {
    u8::from(crate::core::urlpolicy::allow_local_http())
}

/// Library version string, so the shell can show which core it loaded.
#[no_mangle]
pub extern "system" fn Java_net_oxge_mdr_MdrCore_nativeVersion<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jstring {
    out(&mut env, env!("CARGO_PKG_VERSION").to_string())
}
