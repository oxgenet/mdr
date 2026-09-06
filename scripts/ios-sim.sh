#!/usr/bin/env bash
# Build mdr for the iOS Simulator, assemble an .app bundle, install and launch it
# on a booted simulator, then capture a screenshot and the app's stdout.
#
# Usage: scripts/ios-sim.sh [markdown-file] [device-name]
#   markdown-file  document bundled into the app and opened at launch
#                  (default: tests/samples/lang/ja.md)
#   device-name    simulator device (default: first available iPhone)
#
# Requires: Xcode with an iOS simulator runtime, rustup with target
#   aarch64-apple-ios-sim (rustup target add aarch64-apple-ios-sim).
# Outputs: target/ios-sim/mdr.app, target/ios-sim/screenshot.png, target/ios-sim/launch.log
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD="${1:-$ROOT/tests/samples/lang/ja.md}"
DEVICE_NAME="${2:-}"
TARGET=aarch64-apple-ios-sim
OUT="$ROOT/target/ios-sim"
APP="$OUT/mdr.app"
BUNDLE_ID=net.oxge.mdr
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
CARGO="${CARGO:-cargo}"

echo "== build ($TARGET)"
(cd "$ROOT" && "$CARGO" build --release --target "$TARGET")

echo "== assemble $APP"
rm -rf "$APP" && mkdir -p "$APP"
cp "$ROOT/target/$TARGET/release/mdr" "$APP/mdr"
cp "$ROOT/ios/Info.plist" "$APP/Info.plist"
cp "$MD" "$APP/document.md"
# copy sibling assets (images) so relative links resolve inside the bundle
for f in "$(dirname "$MD")"/*.png "$(dirname "$MD")"/*.jpg "$(dirname "$MD")"/*.svg; do
  [ -f "$f" ] && cp "$f" "$APP/" || true
done
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$APP/" 2>/dev/null || true
codesign -s - --force "$APP" >/dev/null

echo "== simulator"
if [ -z "$DEVICE_NAME" ]; then
  UDID=$(xcrun simctl list devices available -j | python -c '
import sys,json
d=json.load(sys.stdin)
for rt,devs in d["devices"].items():
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"].startswith("iPhone"): print(x["udid"]); sys.exit(0)
')
else
  UDID=$(xcrun simctl list devices available -j | python -c '
import sys,json
name=sys.argv[1]; d=json.load(sys.stdin)
for rt,devs in d["devices"].items():
    for x in devs:
        if x["name"]==name: print(x["udid"]); sys.exit(0)
' "$DEVICE_NAME")
fi
[ -n "$UDID" ] || { echo "no iPhone simulator found"; exit 1; }
echo "device: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true

echo "== install + launch"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
: > "$OUT/launch.log"
# --console-pty streams the app's stdout/stderr; run it in the background for a bounded time
( xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" -v > "$OUT/launch.log" 2>&1 & echo $! > "$OUT/launch.pid" )
sleep "${MDR_IOS_WAIT:-10}"

echo "== screenshot"
xcrun simctl io "$UDID" screenshot "$OUT/screenshot.png" >/dev/null
echo "screenshot: $OUT/screenshot.png"

echo "== app log"
sed -n '1,40p' "$OUT/launch.log" || true
# --- assertions (exit non-zero on failure so this can run as an e2e test) ---
fail=0
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
  echo "PASS: app process is running"
else
  echo "FAIL: app process not found (check launch.log)"; fail=1
fi
if grep -q "webview: html_body length=" "$OUT/launch.log"; then
  echo "PASS: document rendered ($(grep -o 'html_body length=[0-9]*' "$OUT/launch.log"))"
else
  echo "FAIL: no render log line"; fail=1
fi
if [ -n "${MDR_EXPECT_LANG:-}" ]; then
  if grep -q "webview: lang=\"$MDR_EXPECT_LANG\"" "$OUT/launch.log"; then
    echo "PASS: lang=$MDR_EXPECT_LANG"
  else
    echo "FAIL: expected lang=$MDR_EXPECT_LANG, got: $(grep -o 'lang=\"[^\"]*\"' "$OUT/launch.log")"; fail=1
  fi
fi
if [ -s "$OUT/screenshot.png" ]; then
  echo "PASS: screenshot $(stat -f %z "$OUT/screenshot.png") bytes"
else
  echo "FAIL: screenshot missing"; fail=1
fi
kill "$(cat "$OUT/launch.pid")" 2>/dev/null || true
[ "$fail" = 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
