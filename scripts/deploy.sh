#!/usr/bin/env bash
# Installs a release build of Oh My TweetDeck into ~/Applications (or $OMT_INSTALL_DIR).
#
# Steps: build the release bundle, smoke-test the staged copy, then swap it in with two
# same-filesystem renames. The previous install is moved (never deleted) into a fresh $TMPDIR
# folder, and put back if the swap fails. A copy already running keeps running: macOS keeps
# the moved bundle's executable alive.
#
# Usage: scripts/deploy.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${OMT_INSTALL_DIR:-$HOME/Applications}"
DEST="$DEST_DIR/OhMyTweetDeck.app"

"$ROOT/scripts/build-app.sh" release

mkdir -p "$DEST_DIR"
STAGE="$(mktemp -d "$DEST_DIR/.omt-stage.XXXXXX")"
cp -R "$ROOT/build/OhMyTweetDeck.app" "$STAGE/OhMyTweetDeck.app"
codesign --verify --strict "$STAGE/OhMyTweetDeck.app"
"$STAGE/OhMyTweetDeck.app/Contents/MacOS/OhMyTweetDeck" --smoke

BACKUP=""
if [ -e "$DEST" ]; then
    BACKUP="$(mktemp -d "${TMPDIR:-/tmp}/omt-previous.XXXXXX")/OhMyTweetDeck.app"
    mv "$DEST" "$BACKUP"
fi
if ! mv "$STAGE/OhMyTweetDeck.app" "$DEST"; then
    [ -n "$BACKUP" ] && mv "$BACKUP" "$DEST"
    echo "deploy: install failed; previous version restored" >&2
    exit 1
fi
rmdir "$STAGE"

echo "Installed $DEST ($("$DEST/Contents/MacOS/OhMyTweetDeck" --smoke))"
[ -n "$BACKUP" ] && echo "Previous version kept at $BACKUP"
exit 0
