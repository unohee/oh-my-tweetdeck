#!/usr/bin/env bash
# Verifies a published release the way a user gets it: downloads the public zip and .sha256,
# checks the checksum, then the Developer ID signature, hardened runtime, stapled notarization
# ticket, Gatekeeper assessment and bundle version. Prints "release ok <version>" on success.
#
# Usage: scripts/verify-release.sh [version]   (default: CFBundleShortVersionString in Resources/Info.plist)
# Env:   OMT_RELEASE_REPO   owner/name on GitHub (default: unohee/oh-my-tweetdeck)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${OMT_RELEASE_REPO:-unohee/oh-my-tweetdeck}"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}"
ZIP_NAME="OhMyTweetDeck-$VERSION-macos.zip"
BASE="https://github.com/$REPO/releases/download/v$VERSION"

fail() { echo "verify-release: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/$ZIP_NAME" "$BASE/$ZIP_NAME" || fail "cannot download $BASE/$ZIP_NAME"
curl -fsSL --retry 3 -o "$tmp/$ZIP_NAME.sha256" "$BASE/$ZIP_NAME.sha256" || fail "cannot download $ZIP_NAME.sha256"
(cd "$tmp" && shasum -a 256 -c "$ZIP_NAME.sha256" >/dev/null) || fail "checksum mismatch"

ditto -x -k "$tmp/$ZIP_NAME" "$tmp/x"
APP="$tmp/x/OhMyTweetDeck.app"
test -d "$APP" || fail "zip does not contain OhMyTweetDeck.app"

codesign --verify --strict --deep "$APP" || fail "signature does not verify"
info="$(codesign -dvv "$APP" 2>&1)"
grep -q 'Authority=Developer ID Application' <<<"$info" || fail "not signed with a Developer ID Application identity"
grep -q 'flags=.*runtime' <<<"$info" || fail "hardened runtime is off"
xcrun stapler validate "$APP" >/dev/null || fail "no valid stapled notarization ticket"
spctl --assess --type execute "$APP" 2>/dev/null || fail "Gatekeeper rejects the app"

built="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[ "$built" = "$VERSION" ] || fail "bundle reports $built, expected $VERSION"

echo "release ok $VERSION"
