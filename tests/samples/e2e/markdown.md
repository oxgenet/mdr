---
title: Markdown edge cases
lang: zh-Hant
author: mdr test suite
---

# Markdown edge cases

Every construct here has broken a Markdown renderer somewhere. The front
matter above must not appear in the output.

`lang: zh-Hant` is deliberate, and deliberately wrong for the content: the
document is mostly English with Japanese and Korean further down, so
detection would never choose Traditional Chinese on its own. If the page
comes out as `zh-Hant`, front matter beat detection.

Note that only CJK tags mean anything here — the language machinery exists
to pick glyph shapes and fonts for Japanese, Chinese and Korean. `lang: en`
would be silently ignored, which is why this fixture does not use it.

## Headings that collide

Two headings with the same text produce the same slug, so the table of
contents ends up with two entries pointing at one anchor. Worth seeing
rather than guessing about.

### Setup

Body under the first Setup.

### Setup

Body under the second Setup.

### The `render()` function — with punctuation, 2024!

Slug generation strips punctuation and inline code; the table of contents
entry should still read sensibly.

### 日本語の見出し

CJK in a heading: the anchor keeps the characters, since they are
alphanumeric to Unicode.

Heading with only an image
--------------------------

![alt text only](assets/pic.png)

## Nesting

- Level one
  - Level two
    - Level three
      1. Ordered inside unordered
      2. Second
         - And back to a bullet
           > A quote inside a list inside a list
           >
           > > Nested twice
- Back to level one

1. Ordered at top level
2. With a paragraph inside

   This paragraph belongs to item 2 and must stay indented under it.

   ```rust
   // A fenced block inside a list item
   fn main() { println!("hello"); }
   ```

3. Third

## Tables

| Left | Centre | Right | Contains \| pipe |
|:-----|:------:|------:|------------------|
| `code` | **bold** | *ital* | a \| b |
| 日本語 | 中文 | 한국어 | emoji ☕ 🚀 |
| a very long cell that should force the table to scroll horizontally on a narrow phone screen rather than overflow the page | x | y | z |

## Task lists

- [x] Done
- [ ] Not done
- [ ] Nested
  - [x] Child done
  - [ ] Child pending

## Footnotes

A statement needing a source[^1], and another[^long-name].

[^1]: The first footnote.
[^long-name]: A footnote with `code`, **bold**, and a [link](https://example.com).

## Emphasis and escapes

**bold**, *italic*, ***both***, ~~struck~~, `inline code`, and intra*word*
emphasis. Escaped: \*not italic\*, \_not italic\_, \`not code\`, \# not a
heading, backslash at end of line\
produces a hard break.

Two spaces at the end of this line  
also produce a hard break.

Entities: &amp; &lt; &gt; &quot; &copy; &#8212;

## Code blocks

```rust
/// Syntax highlighting, and a fence containing what looks like a fence.
fn main() {
    let s = "```";
    println!("{s}");
}
```

```kdl
// The project ships a custom KDL grammar for highlight.js
backend "webview"
toc #true
```

```
No language tag at all — plain monospace, no highlighting.
```

    An indented code block, which is a different construct entirely
    and must not be highlighted.

```json
{"nested": {"deeply": {"is": ["fine", 1, true, null]}}}
```

## Raw HTML

comrak runs with `render.unsafe = true`, so this passes through.

<details>
<summary>A collapsed section</summary>

Hidden content with a [link](https://example.com) and `code`.

</details>

<p align="center"><img src="assets/pic.png" alt="centred" width="80"/></p>

<span style="color: rebeccapurple">Inline styled span.</span>

<!-- An HTML comment, which should not be visible. -->

## Long content

Anunbrokenstringofcharacterswithnospacesatallthatgoesonforalongtimeandwouldoverflowanarrowscreenunlessoverflowwrapisapplied.

A line with a very long URL in it: https://example.com/a/very/long/path/that/keeps/going/and/going?with=query&params=too&more=values#and-a-fragment

## Mixed scripts

English, 日本語, 简体中文, 繁體中文, 한국어, Ελληνικά, Русский, العربية,
עברית — all in one paragraph, with emoji ☕🚀✅ and symbols ±≠≈∞.

## Empty and degenerate

Two consecutive horizontal rules:

---

***

An empty list item:

-
- after an empty one

A blockquote with nothing in it:

>

The end.
