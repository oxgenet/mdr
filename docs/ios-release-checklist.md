# iOS release & monetisation checklist

The counterpart of `android-release-checklist.md`, split the same way: what
the code does, and what only a person with the App Store Connect account can
do. The code is in place and tested; what is left is account and portal work.

---

## 0. Where this stopped, and why

`ios/build-device.sh` was run for the first time on 2026-09-18. It gets as far
as the archive and then fails on **one** thing:

```
error: Provisioning profile "iOS Team Provisioning Profile: net.oxge.mdr"
doesn't match the entitlements file's value for the
com.apple.security.application-groups entitlement.
```

`-allowProvisioningUpdates` registered both App IDs and issued profiles, and
the App Groups capability is enabled on them — but the group array is empty:

```
application-identifier = M6RHW924NW.net.oxge.mdr
com.apple.security.application-groups = Array { }      <- nothing in it
```

`xcodebuild` can create App IDs, certificates and profiles. It **cannot create
an App Group**. That is §2 below, it takes about two minutes, and nothing else
is blocking.

Everything downstream of it is already proven. With the App Group entitlement
temporarily removed, the full archive → export → verify path ran clean and
produced an `Apple Distribution`-signed `.ipa` carrying build 108 in both the
app and the extension.

## 1. Team and account (person)

| | Value |
|---|---|
| Team ID | `M6RHW924NW` |
| Team | OPUSIFY IT SOLUTIONS PRIVATE LIMITED |
| Signing certificate on this Mac | `Apple Development: Gajendra Jadoun (VL5H22CX9H)`, expires 2027-08-25 |
| Distribution certificate | created automatically during the first archive |

The Mac is signed in and automatic signing works. Worth confirming the
person named on the certificate is who you expect — the brief said Dhruv.

## 2. Create the App Group (person, ~2 min) — **the current blocker**

Apple Developer portal → Certificates, Identifiers & Profiles → **Identifiers**
→ the **App Groups** tab → register:

```
group.net.oxge.mdr
```

Then, under **Identifiers → App IDs**, for **both** `net.oxge.mdr` and
`net.oxge.mdr.share`: edit → App Groups → Configure → tick
`group.net.oxge.mdr` → Save.

Then re-run the archive; `-allowProvisioningUpdates` refreshes the profiles.

```bash
DEVELOPMENT_TEAM=M6RHW924NW ios/build-device.sh
```

Without this the Share Extension cannot work at all: the app and the
extension pass documents through the shared container, which *is* the App
Group.

## 3. Paid Applications Agreement and banking (person, can take days)

> **Confirmed active on 2026-09-18.** Nothing here is blocking; the section is
> kept because it is the thing to re-check whenever purchases stop working.


**App Store Connect → Business (Agreements, Tax, and Banking).** No in-app
purchase can be created, let alone sold, until the **Paid Applications**
agreement is active with banking and tax details completed. On Android this
was the long pole; expect the same here. Start it before anything else.

Until it is active the three products cannot even be created, and the Support
section will keep showing *"In-app support is not available on this device
right now."*

## 4. Create the app record and the three purchases (person, ~15 min)

App Store Connect → **Apps → +** → New App, bundle ID `net.oxge.mdr`.

**App Store names are globally unique**, unlike Google Play.

> **Registered on 2026-09-18 as `Markdown Reader`.** Note this is *not*
> identical to the Play listing, which is "Markdown Reader — mdr". Deliberate
> as far as anyone here knows, but worth keeping in mind when writing store
> copy or comparing the two listings — and worth making the subtitle carry
> "mdr" so the brand is not lost on the App Store side.

Then **Features → In-App Purchases → +**, all three **Consumable**, with IDs
matching `SupportCatalogue` exactly. A typo shows up at runtime only as
"in-app support is not available", which is indistinguishable from the
products not existing yet.

| Product ID | Type | Reference name | Suggested JP price |
|---|---|---|---|
| `tip_coffee_1` | Consumable | One Coffee | ¥300 |
| `tip_coffee_2` | Consumable | Two Coffees | ¥600 |
| `tip_boost` | Consumable | Give Development a Boost | ¥1,000 |

The same three IDs are used on Play, so the two listings stay legible side by
side. The app never hardcodes an amount — it shows `product.displayPrice`, so
other storefronts get their own currency. Set a sensible price per market
rather than letting auto-conversion produce oddities.

In-app purchases are reviewed **with a build**, so submit them alongside the
first TestFlight submission for review.

## 5. Build and upload (machine)

```bash
DEVELOPMENT_TEAM=M6RHW924NW ios/build-device.sh            # archive + .ipa
DEVELOPMENT_TEAM=M6RHW924NW ios/build-device.sh --upload   # + TestFlight
```

`--upload` needs an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_PATH`). Without one the script stops and tells you to use **Xcode →
Window → Organizer → Distribute App**, which uses the signed-in account and
needs no key.

The build number comes from the commit count, or `MDR_BUILD_NUMBER`. App Store
Connect rejects a build number it has already seen, so it must increase on
every upload — this is why `CFBundleVersion` is no longer the hardcoded "1"
that would have failed the second upload.

## 6. Testing the tip jar

Unlike Play, iOS **can** exercise purchases locally: `ios/MdrApp/Mdr.storekit`
defines the three consumables, and both the scheme and `MdrApp.xctestplan`
reference it.

One caveat found on 2026-09-18: **plain `xcodebuild` does not apply it**. The
test plan's `storeKitConfigurationFileReference` is ignored (pointing it at a
file that does not exist raises no error), `SKTestSession` reports
`notEntitled`, and storekitd answers from the real Media API —
"Requesting products from Media API… Ignoring empty product response" in the
simulator log. From Xcode's own test runner the configuration *is* applied.

So `StoreTests` skips rather than fails under `xcodebuild`, with the reason in
the skip message. **Run it once from Xcode (Cmd-U) before the first upload** —
that is the run that actually covers the purchase. Everything not needing a
store (catalogue IDs, price ordering, all four screen states) runs headlessly
and is covered by the other 41 tests.

After the first build reaches TestFlight, test again in the **sandbox**:
App Store Connect → Users and Access → Sandbox Testers, then sign in with that
account on the device under Settings → App Store → Sandbox Account.

## 7. Policy notes worth knowing

- **In-app purchase is mandatory** for in-app support payments, exactly as on
  Play. A button linking out to Ko-fi, PayPal or GitHub Sponsors risks
  rejection, which is why there is deliberately no such fallback.
- **Apple's cut** is 15% under the Small Business Program (which must be
  applied for; it is not automatic) and 30% otherwise. A ¥300 tip nets roughly
  ¥255 at 15%.
- **Tips must not unlock anything.** The moment a tier grants a feature it
  stops being a donation. `StoreTests.testATipUnlocksNothing` asserts no
  entitlement is created.
- **Consumables must be finished.** `Transaction.finish()` is the counterpart
  of Android's consume; an unfinished consumable is redelivered on every
  launch and cannot be bought again.
- **Export compliance** is answered in the Info.plist
  (`ITSAppUsesNonExemptEncryption = false`), so builds no longer sit in
  "Missing Compliance". mdr does no encryption beyond HTTPS.
- **Privacy policy**: https://oxgenet.github.io/mdr/privacy-policy — App Store
  Connect requires the URL on the listing. mdr collects nothing.

## 8. Still unverified

- **The Share Extension has never run.** App Groups do not work on an unsigned
  simulator build, so the first signed device install is its first real test.
  Check share-to-mdr from Safari or Files once it installs.
- **The purchase flow on a real storefront**, which needs §3 and §4 first.
- **The device build itself.** It has never been installed on hardware. Note
  that until 2026-09-18 the device archive linked no Rust core at all (it
  picked up a `libmdr.dylib` from the build directory by absolute path, which
  only resolves in the simulator); that is fixed, but "it archives" is not yet
  "it runs on a phone".

---

## Status

| | State |
|---|---|
| Settings screen (reading prefs, Support, About) | done, 41 unit + 9 UI tests pass |
| StoreKit 2 tip jar, 3 consumable tiers | done; purchase path covered only from Xcode's runner |
| English + Japanese strings | done |
| Build number, export compliance, distribution signing | done and verified in an exported .ipa |
| Static linking of the Rust core | **fixed** — was silently absent from device builds |
| App Group `group.net.oxge.mdr` | **not created — §2, blocks the archive** |
| Paid Applications agreement + banking | active (confirmed 2026-09-18) |
| App record `Markdown Reader` (net.oxge.mdr) | created 2026-09-18 |
| App Store Connect API key | created; Key ID `C78543TCSU` |
| 3 in-app purchases | **not created — §4** |
| First TestFlight upload | **blocked on §2** |
