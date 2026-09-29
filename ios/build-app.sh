#!/usr/bin/env bash
# Build the iOS shell (Swift app + Rust core) for the simulator and run the
# test suites against it: MdrAppTests (the Rust core across the C ABI) and
# MdrUITests (the app driven through its real UI).
#
# This used to boot the app and grep NSLog for `[mdr-ios] opened` / `rendered`.
# That could not tell a regression from a renamed log line, and said nothing
# about whether anything reached the screen. `xcodebuild test` reports which
# assertion failed instead.
#
# Usage: ios/build-app.sh [markdown-file] [device-name]
# Env:   MDR_EXPECT_LANG   expected BCP 47 tag for the document (optional)
#        MDR_SKIP_UITESTS  set to 1 to run only the unit tests (faster)
# Requires: Xcode, xcodegen (brew install xcodegen), rustup target aarch64-apple-ios-sim
# Outputs: target/ios-app/MdrApp.app, target/ios-app/screenshot.png,
#          target/ios-app/TestResults.xcresult
set -euo pipefail
export PATH="/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The e2e fixture. Defaults to the shared set in tests/samples/e2e, the same
# documents tests/fixtures.rs renders on every platform and Android's
# FixtureRenderTest renders through JNI. The old default, samples/lang/ja.md,
# was 292 bytes of plain text: it proved a document reached the screen and
# almost nothing else.
MD="${1:-$ROOT/tests/samples/e2e/markdown.md}"
DEVICE_NAME="${2:-}"
OUT="$ROOT/target/ios-app"
BUNDLE_ID=net.oxge.mdr
mkdir -p "$OUT"

echo "== rust core (aarch64-apple-ios-sim, staticlib, no LTO/bitcode for Xcode's linker)"
(cd "$ROOT" && CARGO_PROFILE_RELEASE_LTO=off RUSTFLAGS="-C embed-bitcode=no" \
  cargo build --release --target aarch64-apple-ios-sim --lib --no-default-features --features svg)

echo "== xcodegen"
(cd "$ROOT/ios/MdrApp" && xcodegen generate --quiet)

# The simulator setup below is unchanged: it picks a device, boots it and
# brings up Simulator.app. Only the assertions at the end are different.
echo "== simulator"
if [ -z "$DEVICE_NAME" ]; then
  UDID=$(xcrun simctl list devices available -j | python3 -c '
import sys,json
d=json.load(sys.stdin)
best=None
for rt,devs in d["devices"].items():
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"].startswith("iPhone"): best=(rt,x["udid"])
if best: print(best[1])')
else
  UDID=$(xcrun simctl list devices available -j | python3 -c '
import sys,json
name=sys.argv[1]; d=json.load(sys.stdin)
for rt,devs in d["devices"].items():
    for x in devs:
        if x["name"]==name: print(x["udid"]); sys.exit(0)' "$DEVICE_NAME")
fi
[ -n "$UDID" ] || { echo "FAIL: no iPhone simulator available"; exit 1; }
# Log which device this is. Navigation-bar layout depends on screen width —
# five bar items fit on a 402pt iPhone 17 Pro and overflow into a "More" menu
# on a 390pt iPhone 16 — so "which simulator" is the first thing you need when
# a UI test passes locally and fails in CI. It is not guessable after the fact.
DEVICE_INFO=$(xcrun simctl list devices available -j | UDID="$UDID" python3 -c '
import sys, json, os
want = os.environ["UDID"]
data = json.load(sys.stdin)
for runtime, devices in data["devices"].items():
    for dev in devices:
        if dev["udid"] == want:
            os_name = runtime.split(".")[-1].replace("-", " ")
            print(dev["name"] + "  (" + os_name + ")")
            sys.exit(0)
')
echo "   device: ${DEVICE_INFO:-$UDID}"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true

# `build-for-testing` first, so the app exists and can be installed before the
# fixture is seeded. The test bundles run against that same build.
echo "== build for testing"
xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrApp \
  -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | grep -E "error:|BUILD" || true
APP="$OUT/DerivedData/Build/Products/Debug-iphonesimulator/MdrApp.app"
[ -x "$APP/MdrApp" ] || { echo "FAIL: app not built"; exit 1; }
rm -rf "$OUT/MdrApp.app" && cp -R "$APP" "$OUT/MdrApp.app"

echo "== install"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$OUT/MdrApp.app"

# The test runner has its own sandbox and cannot write into the app's, so the
# fixture is seeded from here. simctl install preserves the data container, so
# this survives the reinstall that `test-without-building` does.
echo "== seed documents into the app's Documents (visible in Files > On My iPhone > mdr)"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
DOCS="$CONTAINER/Documents"
rm -rf "$DOCS" && mkdir -p "$DOCS"
# Copy the fixture's whole directory, not just its siblings. The e2e fixtures
# keep their images in assets/, and a flat glob of *.png/*.svg would silently
# leave every local image missing — images.md would then render as if the
# embedding had broken, which reads as a regression rather than a setup bug.
cp -R "$(dirname "$MD")"/. "$DOCS"/
# ja.md as well, so content detection still has an end-to-end case: the chosen
# fixture proves front matter *overrides* detection, which is a different
# thing from detection working at all.
cp "$ROOT/tests/samples/lang/ja.md" "$DOCS/" 2>/dev/null || true
NAME=$(basename "$MD")
echo "   fixture: $NAME"
echo "   seeded:  $(cd "$DOCS" && ls | tr '\n' ' ')"
[ -d "$DOCS/assets" ] && echo "   assets:  $(cd "$DOCS/assets" && ls | tr '\n' ' ')" || echo "   assets:  (none)"

# Xcode forwards TEST_RUNNER_-prefixed variables into the test processes with
# the prefix stripped. MDR_EXPECT_LANG is the same knob the old script had.
echo "== test ($NAME${MDR_EXPECT_LANG:+, expecting lang=$MDR_EXPECT_LANG})"
rm -rf "$OUT/TestResults.xcresult"
# macOS still ships bash 3.2, where `"${arr[@]}"` on an empty array trips
# `set -u`; the `+` expansion below keeps it quiet.
SKIP=()
[ "${MDR_SKIP_UITESTS:-0}" = "1" ] && SKIP=(-skip-testing:MdrUITests)
set +e
TEST_RUNNER_MDR_FIXTURE="$NAME" \
TEST_RUNNER_MDR_EXPECT_LANG="${MDR_EXPECT_LANG:-}" \
xcodebuild -project "$ROOT/ios/MdrApp/MdrApp.xcodeproj" -scheme MdrApp \
  -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$OUT/TestResults.xcresult" \
  ${SKIP[@]+"${SKIP[@]}"} \
  test-without-building 2>&1 | tee "$OUT/test.log" \
  | grep -E "^Test Case|error:|failed|Executed [0-9]+ tests|\*\* TEST"
rc=${PIPESTATUS[0]}
set -e

xcrun simctl io "$UDID" screenshot "$OUT/screenshot.png" >/dev/null 2>&1 || true
echo "screenshot: $OUT/screenshot.png"
echo "results:    $OUT/TestResults.xcresult"

if [ "$rc" = 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL — open $OUT/TestResults.xcresult, or read $OUT/test.log"
  exit 1
fi
