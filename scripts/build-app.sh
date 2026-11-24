#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it into build/OhMyTweetDeck.app.
# Always run the app from the bundle: the fixed CFBundleIdentifier scopes the
# WKWebView data store (your logins) and the Keychain items.
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

# Ad-hoc signature so macOS keeps a stable identity for Keychain access on this machine.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
