# App Store listing — Markdown Reader (`net.oxge.mdr`, App ID 6813458477)

Everything App Store Connect asks for on the version page, ready to paste.
English and Japanese, because the app ships both and the App Store indexes
each localisation's keywords separately — a Japanese keyword set is free
reach that an English-only listing throws away.

Field limits are Apple's and are enforced on save. The counts here were
measured, not estimated.

---

## 1. App information (once, not per version)

| Field | Value |
|---|---|
| Name | `Markdown Reader` |
| Bundle ID | `net.oxge.mdr` |
| Primary category | Productivity |
| Secondary category | Developer Tools |
| Content rights | Contains no third-party content |
| Age rating | 4+ (see §5) |
| Privacy Policy URL | https://oxgenet.github.io/mdr/privacy-policy |
| Price | **Free** |

The app is free. The three in-app purchases are optional tips that unlock
nothing — that is the product concept, not a launch promotion, and the copy
below leads with it because "free" is the single most load-bearing word on
the page.


The Play listing is "Markdown Reader — mdr". The App Store name is shorter
because names are globally unique there and the suffix bought nothing; the
subtitle carries `mdr` instead.

---

## 2. English (en-US)

### Subtitle (30 max)

```
mdr: free, Mermaid, offline
```

### Promotional text (170 max — editable without a new build)

```
Free to use. Mermaid diagrams drawn natively, pinch to zoom, Japanese, Chinese and Korean typography done right. Opens instantly. Nothing leaves your device.
```

### Keywords (100 max, comma-separated, no spaces)

```
mermaid,md,diagram,flowchart,sequence,uml,viewer,notes,docs,readme,preview,editor,offline,free
```

"markdown" and "reader" are deliberately absent: both are already in the app
name, which Apple indexes. Repeating them wastes the 100 characters. "gfm"
was dropped for "free", which people actually search for.

### Description (4000 max)

```
Markdown, the way you actually read it. Free, with no ads and no account.

mdr opens a Markdown file and shows you the document — not a text editor, not a browser tab, not a half-rendered preview. Mermaid diagrams are drawn. Tables line up. Japanese, Chinese and Korean text gets the right glyph shapes. It opens instantly, because the renderer is a native Rust core rather than a web app in a wrapper.

Built for the way people write now: AI tools produce Markdown constantly — specs, analyses, documentation, all of it full of diagrams and tables. mdr is a fast way to read that on a phone.

WHAT IT DOES

• Mermaid diagrams rendered natively — flowcharts, sequence, class, state, ER, Gantt, pie
• Pinch to zoom any diagram. Large ones stay readable; small ones stay small
• Table of contents built from your headings, one tap away
• Search within a document
• Edit and save in place — your file, not a copy of it
• Opens files from Files, iCloud Drive, and anywhere the document browser reaches
• Share sheet support: send Markdown to mdr from any app
• GitHub-flavoured Markdown: tables, task lists, footnotes, strikethrough, fenced code

FREE, AND PRIVATE BY DEFAULT

mdr is free to use. Every feature listed above is in the app from the moment you install it — there is no trial, no subscription, no paid tier and nothing held back.

It collects nothing either. No account, no sign-in, no analytics, no tracking, no ads. Documents are rendered on your device.

Images that a document links from the web stay off until you turn them on. Plain http is refused for public sites and permitted only for localhost, private addresses and *.local — so a NAS or a development server still works, and nothing else does.

JAPANESE, CHINESE AND KOREAN

The document language is detected from the content, declared per document in front matter, or chosen in Settings. This selects glyph shapes and fonts — the difference between CJK text that reads naturally and text that looks subtly wrong.

OPEN SOURCE

mdr is MIT-licensed and developed in the open at github.com/oxgenet/mdr, based on the original mdr by Clever Cloud (MIT).

BUYING THE DEVELOPER A COFFEE

If mdr turns out to be useful, Settings has an optional tip — the price of a coffee, once, if you feel like it.

It unlocks nothing. There is deliberately no feature behind it, no badge, no "supporter" mode, and the app never asks twice. It is a thank-you, not a purchase.
```

### What's New (first release)

```
First release. Free to use.

• Read Markdown with Mermaid diagrams rendered natively
• Pinch to zoom diagrams
• Table of contents, in-document search, edit and save in place
• Japanese, Chinese and Korean typography
• Open from Files and iCloud Drive, or share into mdr from any app
```

---

## 3. Japanese (ja)

### Subtitle (30 max)

```
mdr — 無料、Mermaid 図も快適
```

### Promotional text (170 max)

```
無料で使えます。Mermaid 図をそのまま描画し、ピンチで拡大。日本語の字形も正しく表示します。Rust 製のコアなので起動は一瞬。データはどこにも送信しません。
```

### Keywords (100 max)

```
マークダウン,mermaid,md,図,作図,ビューア,ドキュメント,メモ,readme,プレビュー,オフライン,技術文書,無料
```

### Description (4000 max)

```
Markdown を、読むためのアプリ。広告なし、アカウント不要、無料。

mdr は Markdown ファイルを開いて「文書」として見せます。テキストエディタでも、ブラウザのタブでも、中途半端なプレビューでもありません。Mermaid の図は描画され、表は整列し、日本語・中国語・韓国語は正しい字形で表示されます。描画エンジンは Rust のネイティブコードなので、起動は一瞬です。

いまの書き方に合わせて作りました。AI ツールは仕様書も分析も資料も Markdown で出力し、その中身は図と表だらけです。mdr はそれを手元で素早く読むためのものです。

できること

• Mermaid をネイティブ描画 — フローチャート、シーケンス、クラス、状態、ER、ガント、円グラフ
• どの図もピンチで拡大。大きな図は読みやすく、小さな図は小さいまま
• 見出しから目次を自動生成。ワンタップで表示
• 文書内検索
• その場で編集して保存 — コピーではなく元のファイルを更新します
• ファイル App や iCloud Drive など、書類ブラウザから開けます
• 共有シート対応 — どのアプリからでも mdr に送れます
• GitHub Flavored Markdown — 表、タスクリスト、脚注、打ち消し線、コードブロック

無料で、プライバシーも守ります

mdr は無料で使えます。上記の機能はすべて、インストールした瞬間から使えます。体験版も、サブスクリプションも、有料プランもありません。機能制限もありません。

収集もしません。アカウント不要、サインイン不要、解析なし、トラッキングなし、広告なし。描画はすべて端末内で完結します。

文書がウェブ上の画像を参照している場合、読み込みは既定でオフです。平文の http は公開サイトに対しては拒否し、localhost・プライベートアドレス・*.local に限って許可します。NAS や開発サーバーは使えて、それ以外は通しません。

日本語・中国語・韓国語

文書の言語は内容から自動判別するほか、フロントマターでの指定、設定での選択ができます。これが字形とフォントを決めます。自然に読める日本語と、どこか違和感のある日本語との差はここにあります。

オープンソース

mdr は MIT ライセンスで、github.com/oxgenet/mdr で開発しています。Clever Cloud による原著作 mdr（MIT）を基にしています。

コーヒー代で応援する

mdr が役に立ったと感じたときだけ、設定からコーヒー一杯分を任意でお送りいただけます。

支払っても機能は何も解放されません。専用機能も、バッジも、「サポーター」表示もありません。アプリが二度お願いすることもありません。買い物でなく、感謝を伝えるためのものです。
```

### What's New

```
最初のリリースです。無料で使えます。

• Mermaid 図をネイティブ描画した Markdown の表示
• 図のピンチ拡大
• 目次、文書内検索、その場での編集と保存
• 日本語・中国語・韓国語の字形に対応
• ファイル App や iCloud Drive から開く、共有シートから送る
```

---

> **Price: Free since 2026-10-13.** It shipped at $0.99 on 2026-09-29 and was
> changed two weeks later. Copy that says a feature is "included in the
> purchase price" is stale — that wording was correct only for those two weeks.

## 4. URLs and copyright

| Field | Value |
|---|---|
| Support URL | https://github.com/oxgenet/mdr/issues |
| Marketing URL | https://github.com/oxgenet/mdr |
| Privacy Policy URL | https://oxgenet.github.io/mdr/privacy-policy |
| Copyright | `2026 Opusify IT Solutions Pvt. Ltd.` |

Support URL is required and must resolve. The issues page qualifies; a
mailto: does not.

---

## 5. Age rating questionnaire

Every question: **None**. The app has no violence, no mature themes, no
gambling, no user-generated content shown to others, no unrestricted web
access.

One question needs care: **"Does your app contain unrestricted web
access?"** → **No.** mdr has no browser and no address bar. It renders local
documents in a WKWebView and follows no navigation to arbitrary pages.

Result: **4+**.

---

## 6. App Privacy

**"Do you or your third-party partners collect data from this app?" → No.**

That answer is defensible field by field:

- No account, no sign-in, no identifiers collected.
- No analytics or crash-reporting SDK is linked. Check with
  `otool -L` on the .ipa if ever in doubt.
- StoreKit is Apple's own framework; purchases are processed by Apple and
  are not developer data collection.
- Remote image loading is off by default, is user-controlled, and fetches
  only what the user's own document references. Nothing is sent to us.

Result on the listing: **Data Not Collected**.

The privacy policy at https://oxgenet.github.io/mdr/privacy-policy says the
same thing, and the two must not disagree — a mismatch between the
questionnaire and the policy is its own rejection reason.

---

## 7. Screenshots — the one thing that needs a machine

**The app is universal** (`TARGETED_DEVICE_FAMILY: "1,2"` in
`ios/MdrApp/project.yml`), so App Store Connect requires **two** sets. An
iPhone-only upload cannot be submitted.

| Set | Accepted sizes (portrait) | Count |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 or 1290 × 2796 | 3–10 |
| iPad 13" | 2064 × 2752 or 2048 × 2732 | 3–10 |

Apple scales these down for smaller devices; no other size needs uploading.

Capture from a simulator — `iPhone 16 Pro Max` and `iPad Pro 13-inch (M4)`
both produce accepted sizes natively:

```bash
xcrun simctl boot "iPhone 16 Pro Max"
xcrun simctl launch --console-pty booted net.oxge.mdr
xcrun simctl io booted screenshot /absolute/path/shot-1.png   # absolute path matters
```

Suggested five, in order — the first two are what sells the app, so they go
first:

1. `diagrams.md` open at a Mermaid flowchart, diagram filling the width
2. The same diagram pinch-zoomed in, showing labels legible at scale
3. Table of contents open beside a long document
4. A Japanese document, showing CJK glyph shaping and a CJK-labelled diagram
5. Settings, showing the image controls (privacy is a selling point here)

`tests/samples/e2e/diagrams.md` and `markdown.md` are the obvious source
documents: they exist to be visually dense, and they are already seeded into
the simulator by `ios/build-app.sh`.

Do not add marketing frames or captions for the first submission. Plain
device screenshots pass review; a mocked-up frame that misrepresents the UI
does not.

---

## 8. Review notes

Paste into App Review Information → Notes:

```
mdr is a free Markdown document reader. No account or sign-in is required —
open any .md file from Files, or use the bundled sample, to see the whole app.

The app is free. In-app purchases: the three items are optional tips ("Support
the Developer"). They are consumables and unlock nothing; every feature of the
app is available without purchasing. This is intentional and is asserted by an automated test
(StoreTests.testATipUnlocksNothing).

Images linked from the web are disabled by default and can be enabled in
Settings. The app has no browser and no arbitrary web navigation.
```

Demo account: not required. Leave the sign-in fields empty.

**Attach all three in-app purchases to the version before submitting.** They
are `READY_TO_SUBMIT`, and first-time purchases are reviewed alongside the
build. If they are not attached to this version, they are not reviewed, and
the tip jar ships dead.

The attach is per-purchase and is *not* done from the version page: open each
in-app purchase and press **Add for Review**. That creates (or joins) a draft
review submission. The app version then joins the same submission — in the UI
by submitting the version normally, or over the API with

```
POST /v1/reviewSubmissionItems   { reviewSubmission: <draft>, appStoreVersion: <version> }
PATCH /v1/reviewSubmissions/<draft>   { submitted: true }
```

`POST /v1/inAppPurchaseSubmissions` is the wrong endpoint for a first version:
it answers `STATE_ERROR.INVALID_REQUEST_ENTITY_STATE_INVALID` until the app is
already live. Verify afterwards that all four items read `WAITING_FOR_REVIEW`;
the version can reach review on its own with the purchases left behind.

Review notes and the description *can* be edited while the version sits in
`WAITING_FOR_REVIEW` — `PATCH` both and the version stays in review. Pulling
the submission back is not necessary for a wording change.

---

## 9. Order of operations

1. Screenshots for both device sizes (§7) — the only step needing a machine.
2. Paste §2 and §3 into the en-US and ja localisations.
3. URLs and copyright (§4).
4. Age rating (§5) and App Privacy (§6) — both are on App Information, not
   the version page, and both block submission while incomplete.
5. Attach the three in-app purchases (§8).
6. Build 135, review notes, submit.

Set the price to **Free** (App Store Connect → Pricing and Availability). The
app was briefly configured at $0.99; free is the product concept — see §1.

The Small Business Program is separate, is Account Holder only, and is **not
retroactive** — 15% versus 30% on every sale made
from enrolment onward, so it is worth doing before the first one, not after.

---

## 10. Google Play, from the same copy

Play's listing is still empty too, and the wording should not diverge between
the two stores — someone comparing them is comparing the same app. The
description and What's New in §2 and §3 transfer verbatim. Only the short
fields differ, because Play's limits do:

| Play field | Limit | en-US | ja |
|---|---|---|---|
| App name | 30 | `Markdown Reader — mdr` | `Markdown Reader — mdr` |
| Short description | 80 | see below | see below |
| Full description | 4000 | §2 description, verbatim | §3 description, verbatim |

Short description, en-US (80 max):

```
Free Markdown reader with native Mermaid diagrams. Offline, no ads, no account.
```

Short description, ja (80 max):

```
Mermaid 図をそのまま描画する無料の Markdown リーダー。オフライン、広告なし、アカウント不要。
```

Play has no keyword field — it indexes the title and both descriptions, so the
keywords in §2 and §3 have nowhere to go and need not be reproduced.

Play also wants a **feature graphic at 1024×500**, which the App Store has no
equivalent of and which does not exist yet. Screenshots can be reused from
`android/store/shots/`; the iOS captures are the wrong device frames for Play.

One asymmetry that matters more than the copy: **on Play, free is a one-way
door.** A free app can never be made paid. Going from paid to free is allowed
and is equally permanent. Apple lets the price move in either direction.
