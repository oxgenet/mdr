# Android release & monetisation checklist

Everything needed to get mdr onto Google Play with a working tip jar, split by
who can actually do it. The code is in place; most of what is left is account
and console work that no script can perform.

---

## 1. Play Console — create the app (person, ~15 min)

1. **Play Console → Create app**
   - App name: e.g. `mdr — Markdown Reader`
   - Default language, App or game: **App**, Free or paid: **Free**
     *(a free app can still take tips; a paid app cannot be switched to free later,
     so decide this deliberately — see §6)*
2. **Set the package name to `net.oxge.mdr`.** It is fixed at first upload and
   can never be changed, so check it against `android/app/build.gradle.kts`
   before submitting anything.
3. Complete the tasks Play lists under **Dashboard → Set up your app**: privacy
   policy URL, app access, ads declaration (mdr has none), content rating,
   target audience, data safety (**mdr collects nothing**), and the store
   listing with icon and screenshots.

## 2. Payments profile (person, can take days)

**Play Console → Setup → Payments profile.** Tips are revenue, so this must
exist and be verified before in-app products can be sold. It needs business
identity and bank details, and verification is not instant — start it early,
because it gates the whole monetisation half.

## 3. Create the three in-app products (person, ~10 min)

**Monetise → Products → In-app products → Create product.** The IDs must match
`Billing.kt` exactly; a typo surfaces at runtime only as "no products
configured".

| Product ID | Type | Name | Suggested JP price |
|---|---|---|---|
| `tip_coffee_1` | **Consumable** | One Coffee | ¥300 |
| `tip_coffee_2` | **Consumable** | Two Coffees | ¥600 |
| `tip_boost` | **Consumable** | Give Development a Boost | ¥1,000 |

Set each to **Active**. Consumable matters: a supporter must be able to tip
more than once, and the app consumes each purchase immediately.

Prices are per storefront. The app never hardcodes an amount — it shows Play's
`formattedPrice`, so other countries see their own currency automatically. Set
a sensible price in each market you enable rather than leaving auto-conversion
to produce oddities like ¥300 → $1.97.

## 4. Signing key (person + machine, one-time)

Play App Signing is on by default; you upload with an **upload key** you keep.

```bash
keytool -genkeypair -v -keystore mdr-upload.jks -keyalg RSA -keysize 4096 \
        -validity 10000 -alias mdr
```

**Back this file up somewhere you will not lose it.** Losing the upload key is
recoverable (Google can reset it); losing it *and* having no Play App Signing
is not.

Then put the details somewhere outside the repo — `~/.gradle/gradle.properties`:

```properties
mdrKeystore=/absolute/path/to/mdr-upload.jks
mdrKeystorePassword=…
mdrKeyAlias=mdr
mdrKeyPassword=…
```

The build reads these (or `MDR_KEYSTORE` etc. from the environment) and signs
the release only when they are present, so ordinary debug builds and CI are
unaffected. **Never commit the keystore or the passwords.**

## 5. Build and upload (machine)

Play requires an **App Bundle**, not an APK, and rejects any reused version
code:

```bash
cd android
./gradlew :app:bundleRelease -PversionCode=2      # increment every upload
# → app/build/outputs/bundle/release/app-release.aab
```

Upload to **Testing → Internal testing** first. Internal testing needs no
review and reaches testers in minutes.

## 6. Testing the tip jar (machine + person)

In-app purchases **cannot be tested from a local debug build**. Play only
recognises a build it has seen, so:

1. Upload the AAB to internal testing
2. Add yourself under **Setup → License testing** — licence testers are
   charged nothing and see "(Test)" purchases
3. Install through the internal-testing link, not by sideloading

Until that is done the Support section correctly shows *"In-app support is not
available on this device right now."* — which
`SettingsActivityTest.theSupportSectionDegradesQuietlyWithoutConfiguredProducts`
asserts, so that path is already covered by a test.

## 7. Policy notes worth knowing

- **Play Billing is mandatory** for in-app support payments. A button linking
  out to Ko-fi, PayPal or GitHub Sponsors risks removal, which is why there is
  deliberately no such fallback in the code.
- **Google's cut** is 15% on the first $1M of annual revenue, 30% above it. A
  ¥300 tip nets roughly ¥255.
- **Tips must not unlock anything.** The moment a tier grants a feature it
  stops being a donation and brings different rules with it. All three tiers
  are purely thank-you purchases.
- **Consumables must be consumed**, which the code does immediately. An
  unacknowledged purchase is auto-refunded by Play after three days.

---

## Status

| | State |
|---|---|
| Settings screen (reading prefs, Support, About) | done, tested on an emulator |
| Play Billing integration, 3 consumable tiers | done, unverified against real products |
| English + Japanese strings | done |
| Release signing config | done, needs a keystore |
| Play Console app, products, payments profile | **not started — §1–3** |
| First internal-testing upload | **not started — §5** |

The unverified part is unavoidable locally: Play only returns products to a
build it recognises, so the purchase flow genuinely cannot be exercised until
§1–§5 are done.
