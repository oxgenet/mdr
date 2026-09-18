#!/usr/bin/env bash
# Build a signed device archive and (optionally) upload to TestFlight.
#
#   DEVELOPMENT_TEAM=ABCDE12345 ios/build-device.sh            # archive + .ipa (ad-hoc export)
#   DEVELOPMENT_TEAM=... ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/AuthKey.p8 \
#     ios/build-device.sh --upload                             # + upload to TestFlight
#
# Without an API key, run it without --upload and drag the .ipa into Xcode's
# Organizer (Window → Organizer → Distribute App); the signed-in account needs
# no key for that route.
#
# Build number: App Store Connect rejects a CFBundleVersion it has already
# seen, so every upload needs a new one. It defaults to the commit count and
# can be overridden with MDR_BUILD_NUMBER. The app and the Share Extension both
# read it from CURRENT_PROJECT_VERSION, which keeps them in lockstep — a
# mismatch between them is itself a rejection.
#
# Prerequisites (one-time, in Xcode / App Store Connect, cannot be automated here):
#   - Apple Developer Program membership; the Team ID above
#   - the app record for net.oxge.mdr created in App Store Connect
#   - App ID net.oxge.mdr (+ net.oxge.mdr.share) with the App Group
#     group.net.oxge.mdr — -allowProvisioningUpdates registers these on the
#     first archive if the account has permission
#   - an App Store Connect API key (Keys → App Store Connect API) for --upload
set -euo pipefail
export PATH="/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/target/ios-device"
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your 10-character Apple Team ID}"
BUILD_NUMBER="${MDR_BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
mkdir -p "$OUT"
echo "== build number $BUILD_NUMBER (override with MDR_BUILD_NUMBER)"

echo "== rust core (aarch64-apple-ios)"
(cd "$ROOT" && CARGO_PROFILE_RELEASE_LTO=off RUSTFLAGS="-C embed-bitcode=no" \
  cargo build --release --target aarch64-apple-ios --lib --no-default-features --features svg)

echo "== xcodegen"
(cd "$ROOT/ios/MdrApp" && xcodegen generate --quiet)

# CODE_SIGN_IDENTITY is deliberately not pinned. It used to force
# "Apple Development", which is the wrong identity for a Release archive bound
# for the App Store: automatic signing picks Apple Distribution for an archive
# and Apple Development for a device build, and saying otherwise only stops it
# choosing correctly. Export re-signs anyway, so this mostly showed up as a
# confusing archive rather than a hard failure — but it is still wrong.
echo "== archive (automatic signing, team $DEVELOPMENT_TEAM)"
xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrApp -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "$OUT/MdrApp.xcarchive" \
  -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive -quiet

METHOD=ad-hoc
[ "${1:-}" = "--upload" ] && METHOD=app-store-connect
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <!-- Keep the build number this script set. Left to Apple, the build number
       is silently rewritten, which makes "which build is this?" unanswerable
       from the repo. -->
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

echo "== export ($METHOD)"
xcodebuild -exportArchive -archivePath "$OUT/MdrApp.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
ls -la "$OUT/export"/*.ipa

# Confirm the export really is distribution-signed. An archive signed for
# development that slipped through export would be rejected by App Store
# Connect after the upload, which is a slow way to find out.
IPA=$(ls "$OUT"/export/*.ipa | head -1)
rm -rf "$OUT/verify" && mkdir -p "$OUT/verify"
unzip -q "$IPA" -d "$OUT/verify"
IDENTITY=$(codesign -dvv "$OUT/verify/Payload/MdrApp.app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
echo "== signed by: ${IDENTITY:-<unsigned>}"
if [ "$METHOD" = "app-store-connect" ] && ! printf '%s' "$IDENTITY" | grep -q "Apple Distribution"; then
  echo "FAIL: an App Store export must be signed by 'Apple Distribution', got '${IDENTITY:-<unsigned>}'"
  echo "      Check that the team has a distribution certificate and that"
  echo "      -allowProvisioningUpdates was able to create the profile."
  exit 1
fi
echo "== CFBundleVersion in the .ipa:"
for plist in "$OUT/verify/Payload/MdrApp.app/Info.plist" \
             "$OUT/verify/Payload/MdrApp.app/PlugIns/MdrShare.appex/Info.plist"; do
  [ -f "$plist" ] && printf '   %-14s %s\n' \
    "$(basename "$(dirname "$plist")")" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null)"
done

if [ "${1:-}" = "--upload" ]; then
  if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
    echo
    echo "No App Store Connect API key set (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH)."
    echo "The .ipa above is ready; upload it from Xcode instead:"
    echo "  Window → Organizer → Archives → Distribute App → App Store Connect"
    echo "That route uses the account already signed in, so it needs no key."
    exit 2
  fi
  echo "== upload to TestFlight (build $BUILD_NUMBER)"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -20
fi
echo "RESULT: OK (build $BUILD_NUMBER)"
