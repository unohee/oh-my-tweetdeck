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
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature (required on Apple Silicon). Its identity is the code hash, so after each
# rebuild macOS may ask once more before the app can read its Keychain items.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
