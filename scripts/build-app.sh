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

# Signing. Default is ad-hoc (local dev). Set OMT_SIGN_ID to a Developer ID identity (or "auto" to
# pick the first "Developer ID Application" identity in the keychain) for a distributable build:
# hardened runtime + secure timestamp, which notarization requires.
# An ad-hoc identity is the code hash, so after each rebuild macOS may ask once more before the
# app can read its Keychain items; a Developer ID signature keeps a stable identity.
SIGN_ID="${OMT_SIGN_ID:-}"
if [ "$SIGN_ID" = "auto" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
  [ -n "$SIGN_ID" ] || { echo "no Developer ID Application identity found" >&2; exit 1; }
fi
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    --entitlements "$ROOT/Resources/OhMyTweetDeck.entitlements" "$APP"
else
  codesign --force --sign - --timestamp=none "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP (${SIGN_ID:-ad-hoc})"
