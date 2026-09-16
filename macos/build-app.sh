#!/usr/bin/env bash
# Build Mdr.app — a macOS bundle around the same `mdr` binary the CLI ships.
#
#   ./macos/build-app.sh                 # host arch only, into target/macos/
#   ./macos/build-app.sh --universal     # arm64 + x86_64 lipo'd together
#   ./macos/build-app.sh --universal --dmg
#
# Signing is ad-hoc by default: enough to run, not enough to clear Gatekeeper,
# so downloads need `xattr -dr com.apple.quarantine` (see README). Set these to
# produce a distributable build instead:
#
#   MACOS_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   MACOS_NOTARY_PROFILE  notarytool keychain profile name, created with
#                         `xcrun notarytool store-credentials`
#
# Both are needed: notarization rejects anything not signed with a Developer ID
# and a hardened runtime.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/target/macos"
APP="$OUT/Mdr.app"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"

UNIVERSAL=0
MAKE_DMG=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --dmg) MAKE_DMG=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> Building mdr $VERSION"
if [ "$UNIVERSAL" = 1 ]; then
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
  cargo build --release --target aarch64-apple-darwin
  cargo build --release --target x86_64-apple-darwin
else
  cargo build --release
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = 1 ]; then
  lipo -create -output "$APP/Contents/MacOS/mdr" \
    "$ROOT/target/aarch64-apple-darwin/release/mdr" \
    "$ROOT/target/x86_64-apple-darwin/release/mdr"
else
  cp "$ROOT/target/release/mdr" "$APP/Contents/MacOS/mdr"
fi
chmod +x "$APP/Contents/MacOS/mdr"

sed "s/__VERSION__/$VERSION/g" macos/Info.plist.in > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"

echo "==> Icon"
ICONSET="$OUT/Mdr.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# rsvg-convert keeps the SVG crisp; sips (always present) is the fallback.
if command -v rsvg-convert >/dev/null 2>&1; then
  render() { rsvg-convert -w "$1" -h "$1" assets/logo-appicon.svg -o "$2"; }
else
  # sips cannot read SVG, so rasterise once at 1024 via the bundled PNG logo
  # scaled up, then downsample. Prefer installing librsvg for a sharp icon.
  BASE="$OUT/base-1024.png"
  sips -s format png -z 1024 1024 assets/logo-128.png --out "$BASE" >/dev/null
  render() { sips -s format png -z "$1" "$1" "$BASE" --out "$2" >/dev/null; }
fi
for sz in 16 32 128 256 512; do
  render "$sz"           "$ICONSET/icon_${sz}x${sz}.png"
  render "$((sz * 2))"   "$ICONSET/icon_${sz}x${sz}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Mdr.icns"
rm -rf "$ICONSET" "$OUT/base-1024.png"

# Developer ID signing when an identity is configured, ad-hoc otherwise.
# Only a Developer ID signature + notarization clears Gatekeeper; ad-hoc builds
# launch fine but need `xattr -dr com.apple.quarantine` after download.
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
  echo "==> Signing (Developer ID: $MACOS_SIGN_IDENTITY)"
  # --options runtime (hardened runtime) and a secure timestamp are both
  # required for notarization to be accepted.
  codesign --force --deep --timestamp --options runtime \
    --sign "$MACOS_SIGN_IDENTITY" "$APP"
else
  echo "==> Signing (ad-hoc — will not clear Gatekeeper)"
  codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose=2 "$APP"

# Notarization: submit, wait, and staple the ticket into the bundle so the app
# validates offline. Needs an App Store Connect API key or an app-specific
# password stored as a notarytool keychain profile.
if [ -n "${MACOS_NOTARY_PROFILE:-}" ]; then
  echo "==> Notarizing"
  NOTARY_ZIP="$OUT/notarize.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  # Staple the .app; the .dmg below is built from the stapled bundle and gets
  # its own staple after creation.
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  rm -f "$NOTARY_ZIP"
fi

echo "==> $APP"
if [ "$MAKE_DMG" = 1 ]; then
  DMG="$OUT/Mdr-$VERSION-macos-universal.dmg"
  [ "$UNIVERSAL" = 1 ] || DMG="$OUT/Mdr-$VERSION-macos-$(uname -m).dmg"
  STAGE="$OUT/dmg"
  rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Mdr $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  if [ -n "${MACOS_NOTARY_PROFILE:-}" ]; then
    # A .dmg is notarized separately from the .app it contains.
    xcrun notarytool submit "$DMG" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
  echo "==> $DMG"
fi
