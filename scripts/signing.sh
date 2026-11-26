# Sourced by build-app.sh and make-dmg.sh: picks the Developer ID certificate.
# SIGN_IDENTITY overrides; otherwise the first "Developer ID Application" identity in the keychain.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application certificate found; set SIGN_IDENTITY." >&2
  exit 1
fi
