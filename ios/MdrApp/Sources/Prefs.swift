import Foundation

/// Reader preferences, the direct counterpart of `Prefs.kt` on Android.
///
/// Only the options the rendering core can actually act on from a shell are
/// here. `remote-images` and `allow-local-http` are deliberately absent: they
/// are process-global switches in Rust that the CLI sets, and neither the C ABI
/// nor the JNI bridge exposes a setter for them, so a toggle would do nothing.
/// Adding one means a new FFI entry point on both platforms.
///
/// Backed by `UserDefaults` rather than a file so the two platforms behave the
/// same way: written immediately, read back on the next render.
struct Prefs {
    private let defaults: UserDefaults

    /// `UserDefaults.standard` in the app; a throwaway suite in tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Show the table-of-contents sidebar when a document opens.
    var showToc: Bool {
        get { defaults.bool(forKey: Self.keyToc) }
        nonmutating set { defaults.set(newValue, forKey: Self.keyToc) }
    }

    /// Explicit BCP 47 tag for CJK rendering, or "" to detect from content.
    /// A document's own front-matter `lang:` still wins over this, exactly as
    /// on the desktop and on Android.
    var lang: String {
        get { defaults.string(forKey: Self.keyLang) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Self.keyLang) }
    }

    /// Fetch images a document links over the network. Default on, matching
    /// the desktop and Android.
    var remoteImages: Bool {
        get { defaults.object(forKey: Self.keyRemoteImages) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.keyRemoteImages) }
    }

    /// Permit plain http on the local network. A narrowing of ``remoteImages``:
    /// the core ignores it while remote images are off, and the UI disables it.
    var allowLocalHttp: Bool {
        get { defaults.object(forKey: Self.keyAllowLocalHttp) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.keyAllowLocalHttp) }
    }

    /// Push the image policy into the core.
    ///
    /// The counterpart of `Prefs.applyImagePolicy()` on Android. These two
    /// settings are process-global in Rust rather than per-render, so they
    /// have to be re-applied on every launch — nothing carries them over.
    func applyImagePolicy() {
        MdrCore.remoteImages = remoteImages
        MdrCore.allowLocalHttp = allowLocalHttp
    }

    static let keyToc = "show_toc"
    static let keyLang = "lang"
    static let keyRemoteImages = "remote_images"
    static let keyAllowLocalHttp = "allow_local_http"

    /// Tags offered in the picker, in the order they are shown.
    /// Must stay identical to `Prefs.LANG_TAGS` on Android.
    static let langTags = ["", "ja", "zh-Hans", "zh-Hant", "ko"]

    /// Index of `tag` in ``langTags``, falling back to 0 ("auto").
    ///
    /// A tag can go stale — it is persisted across upgrades and could name a
    /// language a later build no longer offers — so an unknown value has to
    /// degrade to auto rather than leave the picker pointing at nothing.
    static func langIndex(_ tag: String) -> Int {
        langTags.firstIndex(of: tag) ?? 0
    }

    /// Localised label for one row of the picker.
    static func langLabel(at index: Int) -> String {
        switch index {
        case 1: return NSLocalizedString("lang_ja", comment: "Japanese")
        case 2: return NSLocalizedString("lang_zh_hans", comment: "Chinese (Simplified)")
        case 3: return NSLocalizedString("lang_zh_hant", comment: "Chinese (Traditional)")
        case 4: return NSLocalizedString("lang_ko", comment: "Korean")
        default: return NSLocalizedString("lang_auto", comment: "Detect automatically")
        }
    }
}
