# Privacy Policy — mdr (Markdown Reader)

**Last updated:** 18 September 2026
**Applies to:** the mdr apps for iOS and Android, published by Opusify IT
Solutions Pvt. Ltd.

## The short version

mdr does not collect, store, or transmit any personal data. There are no
accounts, no analytics, no advertising, no tracking, and no telemetry of any
kind. Your documents are read on your device and never leave it.

## What the app does with your documents

Markdown files you open are read directly from the location you chose, rendered
on your device, and displayed. Their contents are never uploaded, copied to a
server, or shared with us or anyone else. We have no way to see what you read
or write.

On iOS, edits are written back to the original file through the system document
machinery. On Android the app currently only reads.

## Images inside documents — the one thing that leaves your device

If a document you open links to an image by web address (for example
`![chart](https://example.com/chart.png)`), the app fetches that image so it can
be displayed. That request goes directly from your device to whoever hosts the
image, and it necessarily reveals your IP address and approximate network
location **to that host** — exactly as it would if you opened the same link in a
browser.

This data goes to the third party hosting the image. It does not come to us, and
we neither see nor log it.

The app applies a fixed policy to these requests: `https` addresses are loaded;
plain `http` is loaded only for addresses on your own local network; everything
else is blocked and shown as a placeholder. Images embedded directly in a
document, and images stored alongside it, involve no network access at all.

## Supporting the developer (in-app purchases)

The apps offer optional one-time payments that support continued development.
They unlock no features and provide no goods — they are voluntary tips.

These are processed entirely by Apple's App Store or Google Play. We never
receive or handle your payment card, billing address, or any other payment
details. Apple and Google provide us only with aggregate sales reporting. Their
handling of your data is covered by their own privacy policies:

- [Apple Privacy Policy](https://www.apple.com/legal/privacy/)
- [Google Privacy Policy](https://policies.google.com/privacy)

## Preferences

Settings you choose in the app — such as the table-of-contents default and the
document language — are stored on your device only. Uninstalling the app
removes them.

## Children

mdr is not directed at children and collects no data from anyone, including
children.

## Permissions

- **Photo library (iOS)** — only when you tap the photo button to insert an
  image into a document. The image is saved next to your document. The app has
  no access to your library at any other time.
- **Internet** — used solely to fetch images a document links to, and to
  communicate with the App Store or Google Play for the optional tips above.

## Open source

mdr is open source under the MIT licence. You can read exactly what it does:
<https://github.com/oxgenet/mdr>

## Changes

If this policy changes, the revised version will be published at this address
with an updated date above.

## Contact

Questions about this policy: open an issue at
<https://github.com/oxgenet/mdr/issues>, or email
<tkykszk@gmail.com>.
