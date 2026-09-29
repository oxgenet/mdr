---
lang: en
---

# External link edge cases

Links exercise the URL policy in `core::urlpolicy` and the relative-link
navigation in the shells. Nothing here should navigate anywhere dangerous,
and nothing should crash the renderer.

## Ordinary web links

- [Plain https](https://example.com/)
- [With a path and query](https://example.com/docs/page?a=1&b=2#section)
- [With a title](https://example.com/ "Hover text")
- [Port number](https://example.com:8443/thing)
- [Trailing slash absent](https://example.com/no-slash)
- Bare autolink: <https://example.com/autolink>
- Bare URL as text: https://example.com/bare-url
- [Uppercase scheme](HTTPS://EXAMPLE.COM/SHOUTING)

## Links that need escaping

- [Spaces encoded](https://example.com/a%20path%20with%20spaces)
- [Parentheses in the URL](https://en.wikipedia.org/wiki/Markdown_(disambiguation))
- [Angle-bracket form](<https://example.com/path with literal spaces>)
- [Quote in the title](https://example.com/ "He said \"hello\"")
- [Ampersand](https://example.com/?a=1&amp;b=2)
- [Unicode path](https://example.com/日本語/ページ)
- [Internationalised domain](https://日本.example/)
- [Very long](https://example.com/one/two/three/four/five/six/seven/eight/nine/ten/eleven/twelve/thirteen/fourteen/fifteen?query=value&another=value&third=value#fragment-that-also-goes-on)

## Reference style

A [reference link][ref] and a [collapsed one][] and a [shortcut].

[ref]: https://example.com/reference
[collapsed one]: https://example.com/collapsed
[shortcut]: https://example.com/shortcut "With a title"

## Non-web schemes

These must render as text or an inert link, never be followed automatically.

- [Email](mailto:someone@example.com)
- [Telephone](tel:+81-3-0000-0000)
- [A file URL](file:///etc/passwd)
- [A data URL](data:text/plain;base64,aGVsbG8=)
- [An unknown scheme](weird-scheme://whatever)

## Links that should not execute anything

The renderer passes raw HTML through, so these are the interesting ones.
None should run when the document is opened.

- [javascript pseudo-URL](javascript:alert&#40;1&#41;)
- <a href="javascript:alert(1)">Raw anchor with a javascript href</a>
- <a href="https://example.com" target="_blank" rel="noopener">Raw anchor, new window</a>

## In-document links

- [To a heading in this file](#ordinary-web-links)
- [To a heading that does not exist](#no-such-heading)
- [Empty fragment](#)

## Links to other documents

Relative Markdown links open in the same window on desktop, resolved
against the current document's directory.

- [A sibling document](markdown.md)
- [A sibling with a fragment](markdown.md#tables)
- [One directory up](../lang/ja.md)
- [A document that is not there](missing.md)
- [Not a document at all](assets/pic.png)

## Links wrapping other things

- [![An image inside a link](assets/pic.png)](https://example.com/image-link)
- [**Bold** and `code` inside a link](https://example.com/rich)
- [A link
  broken across lines](https://example.com/wrapped)

## Degenerate

- [Empty target]()
- [Whitespace target]( )
- [Just a fragment](#)
- []( https://example.com/empty-text )
- [Unclosed bracket](https://example.com/fine)
