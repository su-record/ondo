#!/bin/bash
# Builds dist/ondo.app: binaries for every arch in ARCHS, the bundle layout, and a Developer ID
# signature with the hardened runtime (needed for SMAppService and notarization).
#
#   scripts/build-app.sh                      universal (arm64 + x86_64)
#   ARCHS=arm64 scripts/build-app.sh          this Mac only, faster
#   SIGN_IDENTITY="Developer ID Application: …" picks a certificate; default is the first one found
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT="${OUT:-$ROOT/dist}"
APP="$OUT/ondo.app"
read -r -a ARCH_LIST <<< "${ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for arch in "${ARCH_LIST[@]}"; do ARCH_FLAGS+=(--arch "$arch"); done

# shellcheck source=signing.sh
source "$ROOT/scripts/signing.sh"

swift build --package-path "$ROOT" -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build --package-path "$ROOT" -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp "$BIN/OndoApp" "$APP/Contents/MacOS/ondo"
cp "$BIN/OndoHelper" "$APP/Contents/MacOS/ondo-helper"
# The CLI shares the name "ondo" with the app executable, so it lives in Helpers.
cp "$BIN/ondo" "$APP/Contents/Helpers/ondo"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/Resources/dev.torylabs.ondo.helper.plist" "$APP/Contents/Library/LaunchDaemons/"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
# Inner code first; the helper's identifier is what the app's XPC code requirement checks.
sign --identifier dev.torylabs.ondo.helper "$APP/Contents/MacOS/ondo-helper"
sign --identifier dev.torylabs.ondo.cli "$APP/Contents/Helpers/ondo"
sign "$APP"
codesign --verify --strict --deep "$APP"

echo "$APP"
