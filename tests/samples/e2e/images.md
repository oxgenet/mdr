---
lang: en
---

# Image edge cases

Local images are embedded as `data:` URIs before the page is built, so
nothing needs to be readable from disk afterwards. Remote ones go through
the policy in `core::urlpolicy`. Each case below states what should happen.

## Local files — embedded

`![](assets/pic.png)` — a real PNG, inlined as base64:

![a small png](assets/pic.png)

With a title:

![with title](assets/pic.png "Hover text")

Through a percent-encoded name, because Markdown encodes spaces:

![encoded name](assets/my%20pic.png)

An SVG, which is rasterised to PNG first so any script inside it cannot run:

![an svg](assets/logo.svg)

Raw HTML, which documents use for sizing:

<img src="assets/pic.png" alt="raw html img" width="60" />
<img alt="attributes before src" src="assets/pic.png" width="60" />

## Local files — should not embed

A file that does not exist. The alt text should show, and the page must
still render everything after it:

![missing file](assets/nope.png)

A file whose contents do not match its extension. Magic-byte validation
rejects it rather than handing the WebView something mislabelled:

![not really a png](assets/broken.png)

Escaping the document's directory, which is refused because images embed
without the reader doing anything:

![outside the folder](../lang/test.png)

## Remote — allowed

https is always permitted, and loads lazily:

![remote https](https://example.com/chart.png)

Plain http to a private address is allowed, because it is your own network:

![nas on the lan](http://192.168.1.10/photo.png)
![localhost dev server](http://localhost:3000/preview.png)
![ipv6 loopback](http://[::1]:8080/img.png)
![mdns name](http://nas.local/share/image.png)

## Remote — blocked, shown as a placeholder

Plain http to a public host:

![public http](http://example.com/insecure.png)

A port outside the allowed set, even on a private address:

![odd port](http://192.168.1.10:22/photo.png)

Credentials in the URL:

![credentials](http://user:password@192.168.1.10/photo.png)

A scheme that is not http(s):

![ftp](ftp://example.com/image.png)

A hostname that merely resolves privately is still treated as public —
there is no DNS lookup, so rebinding cannot turn a public name inward:

![looks internal](http://internal.corp.example/logo.png)

## Already self-contained

A `data:` URI passes straight through, untouched:

![inline data uri](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==)

## Degenerate

An image with no alt text:

![](assets/pic.png)

An image with an empty target:

![empty target]()

An image inside a link, inside emphasis:

*[![nested](assets/pic.png)](https://example.com/)*

Two images on one line: ![one](assets/pic.png) ![two](assets/pic.png)

The end — if this line renders, nothing above aborted the page.
