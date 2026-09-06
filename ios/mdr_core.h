// C ABI of the mdr rendering core (Rust staticlib `libmdr.a`).
// All strings are UTF-8 and NUL-terminated. Every char* returned by the
// library must be released with mdr_free().
#ifndef MDR_CORE_H
#define MDR_CORE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Full HTML page (viewer/editor UI included) for `markdown`.
/// base_dir: directory used to resolve relative images (embedded as data URIs).
/// lang: explicit BCP 47 tag ("ja", "zh-Hant", ...) or "" for automatic.
char *mdr_render_page(const char *markdown, const char *base_dir, const char *lang, bool editor, bool toc);

/// JavaScript that updates an already loaded page (body, TOC, lang attribute).
char *mdr_render_update_js(const char *markdown, const char *base_dir, const char *lang);

/// Resolved language tag for the document ("" when none).
char *mdr_detect_lang(const char *markdown, const char *lang);

/// Library version.
char *mdr_version(void);

void mdr_free(char *p);

#ifdef __cplusplus
}
#endif
#endif
