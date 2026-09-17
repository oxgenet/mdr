#!/usr/bin/env bash
# Behaviour tests for Mdr.app, driven through AppleScript.
#
# `ci.yml`'s macos-app job builds the bundle and checks it is well formed, but
# nothing exercised the app's launch paths. This does: the window title is
# `mdr - <path>` (Doc::title), so `name of first window` is enough to tell
# which document is on screen, and that is what makes document switching
# assertable without touching pixels. LEARNINGS.md:21 is where this trick
# comes from.
#
# Usage: macos/test-app.sh [path/to/Mdr.app]
#        (defaults to target/macos/Mdr.app; builds it if missing)
#
# Not run in CI by default: reading another app's windows goes through System
# Events, which needs Accessibility permission that a CI runner cannot grant.
# Set MDR_SKIP_APPLESCRIPT=1 to run only the parts that do not need it.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="${1:-$ROOT/target/macos/Mdr.app}"
BIN="$APP/Contents/MacOS/mdr"

if [ ! -x "$BIN" ]; then
  echo "== building Mdr.app (not found at $APP)"
  ./macos/build-app.sh
fi
[ -x "$BIN" ] || { echo "FAIL: no executable at $BIN"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mdr-macos-test.XXXXXX")"
trap 'rm -rf "$WORK"; osascript -e "tell application \"Mdr\" to quit" >/dev/null 2>&1 || true' EXIT

fail=0
pass() { echo "PASS: $1"; }
fails() { echo "FAIL: $1"; fail=1; }

# --- fixtures: two documents in different directories, linking to each other
mkdir -p "$WORK/sub"
printf '# Alpha\n\n[to beta](sub/beta.md)\n' > "$WORK/alpha.md"
printf '# Beta\n\n[back to alpha](../alpha.md)\n' > "$WORK/sub/beta.md"

# --- 1. the bundled binary works at all
if "$BIN" --version >/dev/null 2>&1; then
  pass "the bundled binary runs"
else
  fails "the bundled binary does not run"
fi

# --- 2. --install-cli refuses to clobber a real binary
# The same rule is unit-tested in tests/install_cli.rs; this runs it against
# the binary that actually ships inside the bundle, which is the one users
# point at.
PREFIX="$WORK/bin"
mkdir -p "$PREFIX"
printf '#!/bin/sh\necho not mdr\n' > "$PREFIX/mdr"
chmod +x "$PREFIX/mdr"
if out=$("$BIN" --install-cli --prefix "$PREFIX" 2>&1); then
  fails "--install-cli overwrote a real binary"
else
  if grep -q 'not a symlink' <<<"$out" && [ "$(cat "$PREFIX/mdr")" = "$(printf '#!/bin/sh\necho not mdr\n')" ]; then
    pass "--install-cli refuses to clobber a real binary"
  else
    fails "--install-cli failed, but not for the documented reason: $out"
  fi
fi

# ...and does install over a link it made itself.
rm -f "$PREFIX/mdr"
if "$BIN" --install-cli --prefix "$PREFIX" >/dev/null 2>&1 \
   && "$BIN" --install-cli --prefix "$PREFIX" >/dev/null 2>&1 \
   && [ -L "$PREFIX/mdr" ]; then
  pass "--install-cli replaces its own symlink"
else
  fails "--install-cli should be repeatable"
fi

if [ "${MDR_SKIP_APPLESCRIPT:-0}" = "1" ]; then
  echo "== skipping the AppleScript checks (MDR_SKIP_APPLESCRIPT=1)"
  [ "$fail" = 0 ] && { echo "RESULT: PASS"; exit 0; } || { echo "RESULT: FAIL"; exit 1; }
fi

# --- 3. launch paths, through the real app
# `open -a` passes an Apple Event, so it carries no CLI flags — only the file.
window_title() {
  osascript <<'OSA' 2>/dev/null || true
tell application "System Events"
  if not (exists process "Mdr") then return ""
  tell process "Mdr"
    if (count of windows) is 0 then return ""
    return name of first window
  end tell
end tell
OSA
}

# Wait until the front window's title contains $1, up to ~15s.
wait_for_title() {
  local want="$1" t=""
  for _ in $(seq 1 60); do
    t="$(window_title)"
    case "$t" in *"$want"*) echo "$t"; return 0 ;; esac
    sleep 0.25
  done
  echo "$t"
  return 1
}

osascript -e 'tell application "Mdr" to quit' >/dev/null 2>&1 || true
sleep 1

echo "== open alpha.md"
open -a "$APP" "$WORK/alpha.md"
if title="$(wait_for_title "alpha.md")"; then
  pass "opening a document shows it in the window title ($title)"
else
  fails "alpha.md never reached the window title (got: '${title:-<none>}')"
  echo "  If this is the first run, grant Accessibility to your terminal:"
  echo "  System Settings > Privacy & Security > Accessibility."
  echo "RESULT: FAIL"
  exit 1
fi

# --- 4. document switching on an already-running app
# This is the Event::Opened path: a second `open -a` must replace the document
# in the existing window, not open a second app.
echo "== switch to sub/beta.md"
open -a "$APP" "$WORK/sub/beta.md"
if title="$(wait_for_title "beta.md")"; then
  pass "a second open switches the document in place ($title)"
else
  fails "the document did not switch to beta.md (title stayed: '${title:-<none>}')"
fi

# The window must have been reused, not added to.
count=$(osascript -e 'tell application "System Events" to tell process "Mdr" to return count of windows' 2>/dev/null || echo "?")
if [ "$count" = "1" ]; then
  pass "switching reuses the window rather than opening another"
else
  fails "expected 1 window after switching, found $count"
fi

# --- 5. back again, which is the relative-link direction (`../alpha.md`)
# Following the link by clicking needs screen coordinates and is left out on
# purpose; what has to hold is that the base directory moves with the
# document, and that is asserted in
# backend::webview::tests::rendering_follows_the_document_across_a_switch.
echo "== switch back to alpha.md"
open -a "$APP" "$WORK/alpha.md"
if title="$(wait_for_title "alpha.md")"; then
  pass "switching back works too ($title)"
else
  fails "could not switch back to alpha.md"
fi

osascript -e 'tell application "Mdr" to quit' >/dev/null 2>&1 || true

[ "$fail" = 0 ] && { echo "RESULT: PASS"; exit 0; } || { echo "RESULT: FAIL"; exit 1; }
