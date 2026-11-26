#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it into build/OhMyTweetDeck.app.
# Always run the app from the bundle: the fixed CFBundleIdentifier scopes the
# WKWebView data store (your logins) and the Application Support folder.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/OhMyTweetDeck.app"

cd "$ROOT"
swift build -c "$CONFIG" --product OhMyTweetDeck
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OhMyTweetDeck"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OhMyTweetDeck"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Signing. Default is ad-hoc (local dev). Set OMT_SIGN_ID to a Developer ID identity (a name or a
# SHA-1 hash) for a distributable build: hardened runtime + secure timestamp, which notarization
# requires. Set it to "auto" to pick an identity that can actually sign (see below).
# An ad-hoc identity is the code hash, so after each rebuild macOS may ask once more before the
# app can read its Keychain items; a Developer ID signature keeps a stable identity.
#
# "auto" lists every "Developer ID Application" identity by SHA-1 hash, in keychain order, and
# probe-signs a throwaway file with each one. The first hash that signs wins. A name is not
# enough: two certificates can share one name, and a CI job (a self-hosted runner that imports the
# same key into a temporary keychain) can make one hash resolve to a key this session cannot use,
# which fails with errSecInternalComponent.
SIGN_ID="${OMT_SIGN_ID:-}"
if [ "$SIGN_ID" = "auto" ]; then
  SIGN_ID=""
  probe="$(mktemp)"
  for hash in $(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ && !seen[$2]++ {print $2}'); do
    cp /usr/bin/true "$probe"
    if codesign --force --sign "$hash" --timestamp=none "$probe" >/dev/null 2>&1; then
      SIGN_ID="$hash"
      break
    fi
    echo "skipping identity $hash: probe signing failed" >&2
  done
  rm -f "$probe"
  [ -n "$SIGN_ID" ] || { echo "no Developer ID Application identity that can sign" >&2; exit 1; }
fi
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    --entitlements "$ROOT/Resources/OhMyTweetDeck.entitlements" "$APP"
else
  codesign --force --sign - --timestamp=none "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP (${SIGN_ID:-ad-hoc})"
