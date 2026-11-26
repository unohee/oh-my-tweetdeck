#!/usr/bin/env bash
# Publishes the GitHub Release for the version in Resources/Info.plist:
# Developer ID build -> notarize + staple -> release v<version> with the zip and its .sha256.
#
# Idempotent and non-destructive, so it is safe to rerun after every merge:
#   - release already has both assets  -> nothing to do, exit 0
#   - release exists, an asset missing -> upload only the missing asset
#   - no release                       -> build, notarize, create it
# It never deletes, edits or overwrites a release, tag or asset.
#
# Usage: scripts/release.sh
# Env:   OMT_SIGN_ID          signing identity for build-app.sh (default: auto = first Developer ID)
#        OMT_NOTARY_PROFILE   notarytool keychain profile for notarize.sh (default: intrect)
#        OMT_RELEASE_REPO     owner/name on GitHub (default: unohee/oh-my-tweetdeck)
# Needs: gh (authenticated), a Developer ID Application identity, the notarytool profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="${OMT_RELEASE_REPO:-unohee/oh-my-tweetdeck}"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"
ZIP_NAME="OhMyTweetDeck-$VERSION-macos.zip"
SHA_NAME="$ZIP_NAME.sha256"
ZIP="$ROOT/build/$ZIP_NAME"
SHA="$ROOT/build/$SHA_NAME"
NOTES="$ROOT/docs/release-notes/$VERSION.md"

command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 1; }

# Current state of the release: "missing", or the list of asset names it already has.
release_exists=0
assets=""
if assets="$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null)"; then
  release_exists=1
fi
has_asset() { grep -qxF "$1" <<<"$assets"; }  # no pipe: see the pipefail note below

if [ "$release_exists" = 1 ] && has_asset "$ZIP_NAME" && has_asset "$SHA_NAME"; then
  echo "release $TAG already published with $ZIP_NAME and $SHA_NAME; nothing to do"
  exit 0
fi

if [ "$release_exists" = 1 ] && has_asset "$ZIP_NAME"; then
  # Only the checksum is missing. Hash the zip that is already published instead of rebuilding:
  # a rebuild would produce a different zip and a checksum that does not match it.
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  gh release download "$TAG" --repo "$REPO" --pattern "$ZIP_NAME" --dir "$tmp"
  (cd "$tmp" && shasum -a 256 "$ZIP_NAME" > "$SHA_NAME")
  gh release upload "$TAG" --repo "$REPO" "$tmp/$SHA_NAME"
  echo "release $TAG: uploaded missing $SHA_NAME"
  exit 0
fi

if [ "$release_exists" = 1 ] && has_asset "$SHA_NAME"; then
  # A checksum without its zip cannot be fixed without replacing an asset. Leave it to a person.
  echo "release $TAG has $SHA_NAME but no $ZIP_NAME; fix it by hand (this script never replaces assets)" >&2
  exit 1
fi

if [ "$release_exists" = 0 ]; then
  test -s "$NOTES" || { echo "missing release notes: $NOTES" >&2; exit 1; }
fi

# Build, sign with Developer ID, notarize, staple, zip.
OMT_SIGN_ID="${OMT_SIGN_ID:-auto}" "$ROOT/scripts/build-app.sh" release
"$ROOT/scripts/notarize.sh" "$VERSION"

built="$(plutil -extract CFBundleShortVersionString raw "$ROOT/build/OhMyTweetDeck.app/Contents/Info.plist")"
[ "$built" = "$VERSION" ] || { echo "built bundle is $built, expected $VERSION" >&2; exit 1; }
# Capture first, then match. Piping codesign into `grep -q` under `set -o pipefail` broke the
# deploy after PR #4: grep exits at the first match, codesign dies of SIGPIPE (141) while still
# writing, and the pipeline reports a failure even though the bundle is signed correctly.
sig="$(codesign -dvv "$ROOT/build/OhMyTweetDeck.app" 2>&1)" \
  || { echo "codesign cannot read the bundle's signature: $sig" >&2; exit 1; }
grep -q 'Authority=Developer ID Application' <<<"$sig" \
  || { echo "bundle is not signed with a Developer ID Application identity" >&2; exit 1; }
test -s "$ZIP" && test -s "$SHA"

if [ "$release_exists" = 1 ]; then
  # The release exists with neither asset (e.g. an interrupted earlier run): attach both.
  gh release upload "$TAG" --repo "$REPO" "$ZIP" "$SHA"
  echo "release $TAG: uploaded $ZIP_NAME and $SHA_NAME"
  exit 0
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  # The tag already exists (pushed by hand): publish the release on it and leave the tag alone.
  gh release create "$TAG" --repo "$REPO" --verify-tag \
    --title "Oh My TweetDeck $VERSION" --notes-file "$NOTES" "$ZIP" "$SHA"
else
  # New tag on the commit this checkout is at; it must already be on GitHub.
  gh release create "$TAG" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Oh My TweetDeck $VERSION" --notes-file "$NOTES" "$ZIP" "$SHA"
fi
echo "release $TAG published: https://github.com/$REPO/releases/tag/$TAG"
