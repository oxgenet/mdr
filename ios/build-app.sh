#!/usr/bin/env bash
# Build the iOS shell (Swift app + Rust core) for the simulator, install it,
# open a sample document through the app's document machinery, screenshot,
# and assert. Mirrors scripts/ios-sim.sh but for the real document-based app.
#
# Usage: ios/build-app.sh [markdown-file] [device-name]
# Requires: Xcode, xcodegen (brew install xcodegen), rustup target aarch64-apple-ios-sim
# Outputs: target/ios-app/MdrApp.app, target/ios-app/screenshot*.png, target/ios-app/launch.log
set -euo pipefail
export PATH="/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD="${1:-$ROOT/tests/samples/lang/ja.md}"
DEVICE_NAME="${2:-}"
OUT="$ROOT/target/ios-app"
BUNDLE_ID=net.oxge.mdr
mkdir -p "$OUT"

echo "== rust core (aarch64-apple-ios-sim, staticlib, no LTO/bitcode for Xcode's linker)"
(cd "$ROOT" && CARGO_PROFILE_RELEASE_LTO=off RUSTFLAGS="-C embed-bitcode=no" \
  cargo build --release --target aarch64-apple-ios-sim --lib --no-default-features --features svg)

echo "== xcodegen"
(cd "$ROOT/ios/MdrApp" && xcodegen generate --quiet)

echo "== xcodebuild"
xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrApp -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO build -quiet 2>&1 | grep -E "error:|BUILD" || true
rm -rf "$OUT/DerivedData/Build/Products/Release-iphonesimulator/MdrApp.app/MdrApp.stale" 2>/dev/null || true
APP="$OUT/DerivedData/Build/Products/Release-iphonesimulator/MdrApp.app"
[ -x "$APP/MdrApp" ] || { echo "FAIL: app not built"; exit 1; }
rm -rf "$OUT/MdrApp.app" && cp -R "$APP" "$OUT/MdrApp.app"

echo "== simulator"
if [ -z "$DEVICE_NAME" ]; then
  UDID=$(xcrun simctl list devices available -j | python -c '
import sys,json
d=json.load(sys.stdin)
for rt,devs in d["devices"].items():
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"].startswith("iPhone"): print(x["udid"]); sys.exit(0)')
else
  UDID=$(xcrun simctl list devices available -j | python -c '
import sys,json
name=sys.argv[1]; d=json.load(sys.stdin)
for rt,devs in d["devices"].items():
    for x in devs:
        if x["name"]==name: print(x["udid"]); sys.exit(0)' "$DEVICE_NAME")
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true

echo "== install"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$OUT/MdrApp.app"

echo "== seed document into the app's Documents (visible in Files > On My iPhone > mdr)"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Documents"
cp "$MD" "$CONTAINER/Documents/"
for f in "$(dirname "$MD")"/*.png "$(dirname "$MD")"/*.svg; do [ -f "$f" ] && cp "$f" "$CONTAINER/Documents/" || true; done
NAME=$(basename "$MD")

echo "== launch (opens $NAME through the document controller)"
: > "$OUT/launch.log"
( xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" -openFile "$NAME" > "$OUT/launch.log" 2>&1 & echo $! > "$OUT/launch.pid" )
sleep "${MDR_IOS_WAIT:-10}"
xcrun simctl io "$UDID" screenshot "$OUT/screenshot.png" >/dev/null 2>&1
echo "screenshot: $OUT/screenshot.png"

echo "== assertions"
fail=0
grep -q "\[mdr-ios\] opened" "$OUT/launch.log" && echo "PASS: document opened via UIDocument" || { echo "FAIL: document not opened"; fail=1; }
grep -q "\[mdr-ios\] rendered" "$OUT/launch.log" && echo "PASS: page rendered in WKWebView" || { echo "FAIL: no render callback"; fail=1; }
if [ -n "${MDR_EXPECT_LANG:-}" ]; then
  grep -q "lang=$MDR_EXPECT_LANG" "$OUT/launch.log" && echo "PASS: lang=$MDR_EXPECT_LANG" || { echo "FAIL: lang mismatch: $(grep -o 'lang=[^ )]*' "$OUT/launch.log")"; fail=1; }
fi
xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID" && echo "PASS: app running" || { echo "FAIL: app not running"; fail=1; }
[ -s "$OUT/screenshot.png" ] && echo "PASS: screenshot" || { echo "FAIL: no screenshot"; fail=1; }
grep "\[mdr-ios\]" "$OUT/launch.log" | sed 's/^/  log: /' | head -8
kill "$(cat "$OUT/launch.pid")" 2>/dev/null || true
[ "$fail" = 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
