#!/usr/bin/env bash
# Notarizes build/OhMyTweetDeck.app with Apple, staples the ticket and writes the release zip.
# Run scripts/build-app.sh with OMT_SIGN_ID=auto first (hardened runtime is required).
#
# Usage: scripts/notarize.sh [version]       (default: CFBundleShortVersionString)
# Env:   OMT_NOTARY_PROFILE  notarytool keychain profile (default: intrect)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/OhMyTweetDeck.app"
PROFILE="${OMT_NOTARY_PROFILE:-intrect}"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")}"
ZIP="$ROOT/build/OhMyTweetDeck-$VERSION-macos.zip"
SUBMIT="$ROOT/build/notarize-submit.zip"

codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait
rm -f "$SUBMIT"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$ROOT/build" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "$ZIP.sha256"
