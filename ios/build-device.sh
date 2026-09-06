#!/usr/bin/env bash
# Build a signed device archive and (optionally) upload to TestFlight.
#
#   DEVELOPMENT_TEAM=ABCDE12345 ios/build-device.sh            # archive + .ipa (ad-hoc export)
#   DEVELOPMENT_TEAM=... ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/AuthKey.p8 \
#     ios/build-device.sh --upload                             # + upload to TestFlight
#
# Prerequisites (one-time, in Xcode / App Store Connect, cannot be automated here):
#   - Apple Developer Program membership; the Team ID above
#   - App ID net.oxge.mdr (+ net.oxge.mdr.share) with the App Group group.net.oxge.mdr
#   - an App Store Connect API key (Keys → App Store Connect API) for --upload
set -euo pipefail
export PATH="/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/target/ios-device"
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your 10-character Apple Team ID}"
mkdir -p "$OUT"

echo "== rust core (aarch64-apple-ios)"
(cd "$ROOT" && CARGO_PROFILE_RELEASE_LTO=off RUSTFLAGS="-C embed-bitcode=no" \
  cargo build --release --target aarch64-apple-ios --lib --no-default-features --features svg)

echo "== xcodegen"
(cd "$ROOT/ios/MdrApp" && xcodegen generate --quiet)

echo "== archive (automatic signing, team $DEVELOPMENT_TEAM)"
xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrApp -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "$OUT/MdrApp.xcarchive" \
  -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="Apple Development" \
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
</dict></plist>
PLIST

echo "== export ($METHOD)"
xcodebuild -exportArchive -archivePath "$OUT/MdrApp.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
ls -la "$OUT/export"/*.ipa

if [ "${1:-}" = "--upload" ]; then
  : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
  echo "== upload to TestFlight"
  xcrun altool --upload-app -f "$OUT"/export/*.ipa -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -5
fi
echo "RESULT: OK"
