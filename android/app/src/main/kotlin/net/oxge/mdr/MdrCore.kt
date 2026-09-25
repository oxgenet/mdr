package net.oxge.mdr

/**
 * Kotlin side of the JNI bridge in `src/jni_bridge.rs`.
 *
 * The direct counterpart of `ios/MdrApp/Sources/MdrCore.swift`: the same four
 * calls into the same Rust rendering core. Nothing here parses Markdown, builds
 * HTML or detects a language — that all happens once, in Rust, so the two
 * phones and the desktop cannot disagree about what a document looks like.
 *
 * The native methods return null only if the JVM refuses to allocate the
 * string; callers get "" instead so a render failure degrades to an empty page
 * rather than a null-pointer crash.
 */
object MdrCore {

    /**
     * Why `libmdr.so` could not be loaded, or null when it loaded fine.
     *
     * Loading is deliberately not allowed to throw out of the class
     * initialiser. An `UnsatisfiedLinkError` there takes down the process on
     * the first touch of this object — which on a device means the app dies at
     * launch with no message, and in a test run aborts every remaining test.
     * A device whose ABI was left out of `abiFilters` would do exactly that.
     */
    val loadError: String? = try {
        System.loadLibrary("mdr")
        null
    } catch (e: UnsatisfiedLinkError) {
        e.message ?: "libmdr.so could not be loaded"
    }

    /** False when the native core is missing; callers should show an error. */
    val isAvailable: Boolean get() = loadError == null

    /**
     * Full HTML page for a document, viewer/editor chrome included.
     *
     * @param baseDir directory that relative image paths resolve against, or
     *   "" when the document came from a provider with no filesystem path.
     * @param lang explicit BCP 47 tag, or "" to detect from the content.
     */
    fun renderPage(
        markdown: String,
        baseDir: String,
        lang: String = "",
        editor: Boolean = false,
        toc: Boolean = false,
    ): String = if (!isAvailable) "" else nativeRenderPage(markdown, baseDir, lang, editor, toc) ?: ""

    /** JavaScript that updates an already loaded page from new Markdown. */
    fun updateScript(markdown: String, baseDir: String, lang: String = ""): String =
        if (!isAvailable) "" else nativeRenderUpdateJs(markdown, baseDir, lang) ?: ""

    /** Resolved language tag for the document, or "" when there is none. */
    fun detectLang(markdown: String, lang: String = ""): String =
        if (!isAvailable) "" else nativeDetectLang(markdown, lang) ?: ""

    /** Version of the Rust core actually loaded, or "" when there is none. */
    val version: String get() = if (!isAvailable) "" else nativeVersion() ?: ""

    /**
     * Whether the loaded core exposes the image URL policy.
     *
     * A `libmdr.so` built before these entry points existed still loads and
     * renders perfectly; only these four symbols are missing, and the JVM
     * resolves a native method on first call, so the absence surfaces as an
     * `UnsatisfiedLinkError` at that moment rather than at load. Probing once
     * lets the settings screen hide controls that would otherwise do nothing.
     */
    val policySupported: Boolean by lazy {
        isAvailable && runCatching { nativeRemoteImages() }.isSuccess
    }

    /** Load images from http(s) URLs at all. Ignored by an older core. */
    fun setRemoteImages(on: Boolean) {
        if (policySupported) runCatching { nativeSetRemoteImages(on) }
    }

    /** Allow plain http for localhost / private addresses. Ignored by an older core. */
    fun setAllowLocalHttp(on: Boolean) {
        if (policySupported) runCatching { nativeSetAllowLocalHttp(on) }
    }

    /** The policy the core is actually applying, not what was last requested. */
    fun remoteImages(): Boolean =
        if (!policySupported) true else runCatching { nativeRemoteImages() }.getOrDefault(true)

    fun allowLocalHttp(): Boolean =
        if (!policySupported) true else runCatching { nativeAllowLocalHttp() }.getOrDefault(true)

    @JvmStatic
    private external fun nativeRenderPage(
        markdown: String,
        baseDir: String,
        lang: String,
        editor: Boolean,
        toc: Boolean,
    ): String?

    @JvmStatic
    private external fun nativeRenderUpdateJs(markdown: String, baseDir: String, lang: String): String?

    @JvmStatic
    private external fun nativeDetectLang(markdown: String, lang: String): String?

    @JvmStatic
    private external fun nativeVersion(): String?

    @JvmStatic
    private external fun nativeSetRemoteImages(on: Boolean)

    @JvmStatic
    private external fun nativeSetAllowLocalHttp(on: Boolean)

    @JvmStatic
    private external fun nativeRemoteImages(): Boolean

    @JvmStatic
    private external fun nativeAllowLocalHttp(): Boolean
}
