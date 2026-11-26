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
# Errors print one line starting with "notarize failed", ahead of the tool's own output, so a log
# that keeps only the start of stderr (auto-claude's deploy record does) still says which step broke.
fail() { echo "notarize failed: $*" >&2; exit 1; }

rc=0
submit_log="$(xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait 2>&1)" || rc=$?
echo "$submit_log"
[ "$rc" = 0 ] || fail "notarytool submit exited $rc: $(tail -1 <<<"$submit_log")"
rm -f "$SUBMIT"
# --wait returns once processing ends, whatever the verdict; only "Accepted" can be stapled.
grep -q 'status: Accepted' <<<"$submit_log" \
  || fail "Apple did not accept the submission: $(grep -m1 'status:' <<<"$submit_log")"

# Stapling fetches the ticket from Apple's CDN. Right after a fast "Accepted" the ticket may not be
# published yet, and stapler fails with error 65 (CloudKit "Record Not Found"). That is what broke
# the deploy after PR #4: the submission was accepted at 09:16:36 UTC and the deploy had failed by
# 09:16:56, while the same steps passed minutes later. Retry until the ticket is out.
stapled=0
for attempt in 1 2 3 4 5 6; do
  if staple_log="$(xcrun stapler staple "$APP" 2>&1)"; then
    echo "$staple_log"
    stapled=1
    break
  fi
  echo "stapler staple failed (attempt $attempt/6): $(tr '\n' ' ' <<<"$staple_log" | cut -c1-300)" >&2
  [ "$attempt" = 6 ] || sleep 20
done
[ "$stapled" = 1 ] || fail "no notarization ticket could be stapled after 6 attempts"
xcrun stapler validate "$APP" || fail "stapler validate rejected the stapled ticket"
spctl --assess --type execute --verbose=2 "$APP" || fail "Gatekeeper (spctl) rejected the app"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$ROOT/build" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "$ZIP.sha256"
