#!/usr/bin/env bash
# Capture the App Store screenshots listed in listing.md §7.
#
#   ios/store/capture-shots.sh              # both required sets
#   ios/store/capture-shots.sh "iPhone 16 Pro Max"
#
# The app is universal, so App Store Connect requires an iPhone 6.9" set and
# an iPad 13" set; an iPhone-only upload cannot be submitted. These two
# simulators produce accepted sizes natively (1290x2796 and 2064x2752), so
# nothing is ever rescaled — a resized screenshot is rejected.
#
# Output: ios/store/shots/<device>/NN-name.png
set -euo pipefail
export PATH="/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/ios/store/shots"
DERIVED="$ROOT/target/store-shots"
BUNDLE_ID=net.oxge.mdr
DEVICES=("${1:-iPhone 16 Pro Max}")
[ $# -eq 0 ] && DEVICES=("iPhone 16 Pro Max" "iPad Pro 13-inch (M4)")

echo "== rust core (aarch64-apple-ios-sim)"
(cd "$ROOT" && CARGO_PROFILE_RELEASE_LTO=off RUSTFLAGS="-C embed-bitcode=no" \
  cargo build --release --target aarch64-apple-ios-sim --lib --no-default-features --features svg)
echo "== xcodegen"
(cd "$ROOT/ios/MdrApp" && xcodegen generate --quiet)

for DEVICE in "${DEVICES[@]}"; do
  echo
  echo "======== $DEVICE ========"
  UDID=$(xcrun simctl list devices available -j | DEV="$DEVICE" python3 -c '
import sys, json, os
want = os.environ["DEV"]
data = json.load(sys.stdin)
best = None
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime: continue
    for dev in devices:
        if dev["name"] == want: best = dev["udid"]
print(best or "")
')
  [ -n "$UDID" ] || { echo "FAIL: no simulator named '$DEVICE'"; exit 1; }
  # Erase first. A simulator remembers a StoreKit configuration once a scheme
  # has enabled it, and that outlives switching schemes — which is how tip
  # prices from the local test catalogue kept reappearing in the Settings
  # shot even after the screenshot scheme stopped setting one. Set
  # MDR_KEEP_SIMULATOR=1 to skip when iterating on framing.
  if [ "${MDR_KEEP_SIMULATOR:-0}" != "1" ]; then
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl erase "$UDID"
  fi
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true

  # A tidy status bar. Apple accepts the real one; this only removes the
  # carrier and battery noise that varies between runs, so re-shooting one
  # image does not leave it visibly different from the rest.
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 2>/dev/null || true

  echo "== build for testing"
  xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrAppShots \
    -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO \
    build-for-testing 2>&1 | grep -E "error:|BUILD" || true

  APP="$DERIVED/Build/Products/Debug-iphonesimulator/MdrApp.app"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"

  # Same fixtures build-app.sh uses, seeded the same way.
  DOCS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents"
  rm -rf "$DOCS" && mkdir -p "$DOCS"
  cp -R "$ROOT/tests/samples/e2e/." "$DOCS"/
  cp "$ROOT/tests/samples/lang/ja.md" "$DOCS/"

  echo "== capture"
  RESULT="$DERIVED/$(echo "$DEVICE" | tr ' ' '-').xcresult"
  rm -rf "$RESULT"
  xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrAppShots \
    -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -resultBundlePath "$RESULT" \
    -only-testing:MdrUITests/StoreShotTests test-without-building 2>&1 \
    | grep -E "^Test Case|error:|\*\* TEST" || true

  DEST="$OUT/$(echo "$DEVICE" | tr ' ' '-' | tr -d '()')"
  rm -rf "$DEST" && mkdir -p "$DEST"
  TMP="$DERIVED/attachments"; rm -rf "$TMP"; mkdir -p "$TMP"
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$TMP" >/dev/null 2>&1
  DEST="$DEST" TMP="$TMP" python3 -c '
import json, os, shutil
tmp, dest = os.environ["TMP"], os.environ["DEST"]
manifest = json.load(open(os.path.join(tmp, "manifest.json")))
n = 0
for test in manifest:
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName") or ""
        if not name or not name[0].isdigit():
            continue
        # "01-flowchart_1_UUID.png" -> "01-flowchart.png"
        clean = name.split("_")[0]
        if not clean.endswith(".png"): clean += ".png"
        shutil.copyfile(os.path.join(tmp, att["exportedFileName"]), os.path.join(dest, clean))
        n += 1
print(f"   {n} screenshots -> {dest}")
'
  xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
  for f in "$DEST"/*.png; do
    [ -f "$f" ] || continue
    printf '   %-28s %s\n' "$(basename "$f")" \
      "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
  done
done
echo
echo "RESULT: OK"
