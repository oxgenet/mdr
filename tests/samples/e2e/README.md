# End-to-end fixtures

Documents that exercise the rendering core the way real content does, rather
than the way a minimal example does. Every e2e harness — desktop, iOS
simulator, Android emulator — should open these, and `tests/fixtures.rs`
renders each one on every CI platform.

The previous e2e fixture was `samples/lang/ja.md`, 292 bytes of plain text.
It proved a document appeared on screen and almost nothing else.

| File | Covers |
|---|---|
| `markdown.md` | GFM edge cases: colliding heading slugs, deep nesting, tables with escaped pipes, footnotes, task lists, raw HTML, escapes, indented vs fenced code, mixed scripts, unbreakable strings |
| `links.md` | External links: every URL policy branch, non-web schemes, `javascript:` hrefs that must stay inert, reference style, in-document anchors, relative document links |
| `images.md` | Local embedding, SVG rasterisation, magic-byte rejection, directory escape, every remote allow/block case, `data:` passthrough |
| `diagrams.md` | Mermaid: each supported type, CJK labels, subgraphs, deliberately tiny and very large diagrams, empty and malformed blocks |
| `assets/` | Files the fixtures reference, including `broken.png`, which is HTML wearing a PNG extension |

## What "passing" means

These are not golden-file tests. Exact output changes whenever the CSS or
the Mermaid renderer does, and pinning it would mean rewriting expectations
on every cosmetic change.

What each fixture asserts instead is that the document survives: a complete
page comes out, nothing panics, and the specific behaviour the fixture is
named for holds — a blocked image becomes a placeholder, front matter does
not reach the body, a malformed diagram degrades to its source.

Several cases are deliberately wrong. `assets/broken.png` is not a PNG,
`assets/nope.png` does not exist, and `links.md` contains `javascript:`
hrefs. They are there because the renderer must handle them, and each is
labelled in the document with what should happen.

## A thing worth knowing

Only CJK language tags mean anything. `core::lang` exists to choose glyph
shapes and fonts for Japanese, Chinese and Korean, so `lang: en` in front
matter is silently ignored and the page falls through to content detection.
`markdown.md` therefore declares `zh-Hant`, which detection would never pick
for its content - if the page comes out as `zh-Hant`, front matter won.

## Adding a case

Put it in the fixture whose subject it matches, say in the prose what should
happen, and add an assertion to `tests/fixtures.rs` if it is a behaviour
worth pinning rather than just content worth rendering.
