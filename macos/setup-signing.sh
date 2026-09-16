#!/usr/bin/env bash
# Check the local signing setup for notarized Mdr.app builds and print exactly
# what is still missing. Run it after creating the Developer ID Application
# certificate in the Apple Developer portal.
#
#   ./macos/setup-signing.sh                        # report status
#   ./macos/setup-signing.sh --notary               # also create the profile
#   MACOS_TEAM_ID=ABCDE12345 ./macos/setup-signing.sh   # pick one of several teams
#
# Set MACOS_TEAM_ID when the keychain holds Developer ID certificates for more
# than one team (e.g. a personal one and an organisation's); without it the
# script refuses to guess.
#
# Nothing here is destructive; the steps that need your password or a browser
# are printed for you to run, not executed.
set -uo pipefail
cd "$(dirname "$0")/.."

PROFILE=mdr-notary
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
miss() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo "==> Signing identities"
# The team id is the parenthesised suffix of the certificate's common name.
CANDIDATES=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" \
  | sed -n 's/.*"\(.*\)".*/\1/p')

if [ -n "${MACOS_TEAM_ID:-}" ]; then
  CANDIDATES=$(printf '%s\n' "$CANDIDATES" | grep "($MACOS_TEAM_ID)" || true)
  [ -z "$CANDIDATES" ] && {
    miss "no Developer ID Application certificate for team $MACOS_TEAM_ID"
    echo "  Present: $(security find-identity -v -p codesigning \
      | grep -c 'Developer ID Application') Developer ID certificate(s)."
    exit 1
  }
fi

COUNT=$(printf '%s' "$CANDIDATES" | grep -c . || true)
if [ "$COUNT" -gt 1 ]; then
  miss "several Developer ID Application certificates — choose one by team id:"
  printf '%s\n' "$CANDIDATES" | sed 's/^/      /'
  echo
  echo "    MACOS_TEAM_ID=<10 chars> ./macos/setup-signing.sh"
  exit 1
fi

IDENTITY=$CANDIDATES
if [ -n "$IDENTITY" ]; then
  ok "Developer ID Application: $IDENTITY"
  TEAM_ID=$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
  ok "Team ID: $TEAM_ID"
else
  miss "no Developer ID Application certificate in the keychain"
  echo
  echo "  It is a different certificate type from 'Apple Development', which"
  echo "  cannot be notarized. Create it once, as the Account Holder:"
  echo
  echo "    1. Keychain Access → Certificate Assistant → Request a Certificate"
  echo "       From a Certificate Authority… → save to disk (this is the CSR)"
  echo "    2. https://developer.apple.com/account/resources/certificates/add"
  echo "       Pick the right team in the selector at the top right FIRST —"
  echo "       a certificate belongs to one team and cannot be moved."
  echo "       → Developer ID Application → upload the CSR → download the .cer"
  echo "    3. Double-click the .cer to add it to the login keychain"
  echo "    4. Re-run this script"
  echo
  echo "  Requires a paid Apple Developer Program membership and the Account"
  echo "  Holder role; a team Admin cannot create Developer ID certificates."
  exit 1
fi

echo
echo "==> Notarization credentials"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  ok "notarytool profile '$PROFILE' works"
elif [ "${1:-}" = "--notary" ]; then
  echo "  Creating profile '$PROFILE'."
  echo "  Use an app-specific password from https://account.apple.com → Sign-In"
  echo "  and Security → App-Specific Passwords (NOT your Apple ID password)."
  xcrun notarytool store-credentials "$PROFILE" --team-id "$TEAM_ID" \
    || { miss "store-credentials failed"; exit 1; }
  ok "notarytool profile '$PROFILE' created"
else
  miss "notarytool profile '$PROFILE' not set up — re-run with --notary"
  exit 1
fi

echo
echo "==> Ready. Build a signed, notarized bundle with:"
echo
echo "    MACOS_SIGN_IDENTITY=\"$IDENTITY\" \\"
echo "    MACOS_NOTARY_PROFILE=$PROFILE \\"
echo "      ./macos/build-app.sh --universal --dmg"
echo
echo "    spctl --assess --type execute --verbose=4 target/macos/Mdr.app"
echo "      # expect: accepted / source=Notarized Developer ID"
echo
echo "==> For CI, set these repository secrets (Settings → Secrets → Actions):"
echo
echo "    MACOS_SIGN_IDENTITY        $IDENTITY"
echo "    MACOS_TEAM_ID              $TEAM_ID"
echo "    MACOS_NOTARY_APPLE_ID      <your Apple ID email>"
echo "    MACOS_NOTARY_APP_PASSWORD  <the app-specific password>"
echo "    MACOS_CERTIFICATE          <base64 of the exported .p12>"
echo "    MACOS_CERTIFICATE_PWD      <password you set on the .p12>"
echo "    MACOS_KEYCHAIN_PWD         <any string; a throwaway CI keychain>"
echo
echo "  Export the .p12 from Keychain Access (right-click the certificate →"
echo "  Export, include the private key), then:"
echo
echo "    base64 -i Certificates.p12 | pbcopy"
