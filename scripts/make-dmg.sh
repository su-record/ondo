#!/bin/bash
# Release build: universal app, notarized and stapled, inside a signed, notarized and stapled DMG.
#
#   NOTARY_PROFILE=<profile> scripts/make-dmg.sh
#   APPLE_API_KEY_PATH=<.p8> APPLE_API_KEY=<key id> APPLE_API_ISSUER=<issuer id> scripts/make-dmg.sh
#
# Notarization uses a notarytool keychain profile (xcrun notarytool store-credentials <profile>) or an
# App Store Connect API key. Either belongs to the developer account, so one made for another app works.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
  NOTARY_AUTH=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
else
  echo "Set NOTARY_PROFILE, or APPLE_API_KEY_PATH, APPLE_API_KEY and APPLE_API_ISSUER." >&2
  exit 1
fi
# shellcheck source=signing.sh
source "$ROOT/scripts/signing.sh"

APP="$ROOT/dist/ondo.app"
DMG="$ROOT/dist/ondo-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

notarize() {
  local output
  output="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait 2>&1)"
  echo "$output"
  if ! grep -q "status: Accepted" <<< "$output"; then
    echo "Notarization of $1 was not accepted; see: xcrun notarytool log <id> with the same credentials" >&2
    exit 1
  fi
}

"$ROOT/scripts/build-app.sh"

# The app is stapled too, so it opens offline even after it leaves the DMG.
ditto -c -k --keepParent "$APP" "$WORK/ondo.zip"
notarize "$WORK/ondo.zip"
xcrun stapler staple "$APP"

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/ondo.app"
ln -s /Applications "$WORK/stage/Applications"
rm -f "$DMG"
hdiutil create -volname "ondo $VERSION" -srcfolder "$WORK/stage" -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

spctl -a -vv "$APP"
spctl -a -vv -t open --context context:primary-signature "$DMG"
echo "sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)  $DMG"
