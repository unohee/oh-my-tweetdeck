<p align="center">
  <img src="omt-logo.svg" width="128" height="128" alt="Oh My TweetDeck logo">
</p>

# Oh My TweetDeck

A TweetDeck-style macOS app for the multi-network era: watch **X, Threads and Instagram**
feeds side by side in columns, and send **one message to all of them** from a single
compose panel.

Inspired by [OldTweetDeck](https://github.com/dimdenGD/OldTweetDeck) (MIT), which brings
the classic TweetDeck back for X. This app takes the idea — parallel columns plus a
compose panel — and applies it across services. It does not include OldTweetDeck code or
the original TweetDeck bundle.

## How it works

| | Columns (reading) | Posting |
|---|---|---|
| **X** | x.com in a WKWebView | Your logged-in x.com session: the app opens x.com's own intent composer prefilled with your text in a visible sheet and presses Post. No API key. |
| **Threads** | threads.com in a WKWebView | Official [Threads API](https://developers.facebook.com/docs/threads/posts) (`graph.threads.com/v1.0`): create container → wait for `FINISHED` → publish. |
| **Instagram** | instagram.com in a WKWebView | Official [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/content-publishing) (`graph.instagram.com`). Professional accounts only, and **every post needs an image** at a public https JPEG URL. |

- No service offers a home-feed API, so columns are the real websites. Every column shares
  one persistent web data store: log in once per service and all its columns stay logged in.
- Columns use a desktop Safari user agent, which gives all three sites a narrow responsive
  layout without "open the app" interstitials (checked 2026-11-24).
- API tokens live in the macOS Keychain, never in files. They are sent in the
  `Authorization` header, not the URL.
- One failing service never blocks the others; each target reports its own result, and the
  draft is kept until every target succeeds.

## Install

Download `OhMyTweetDeck-<version>-macos.zip` from the
[Releases page](https://github.com/unohee/oh-my-tweetdeck/releases/latest), unzip it, and
move `OhMyTweetDeck.app` to Applications. Release builds are signed with a Developer ID
certificate (hardened runtime) and notarized by Apple, so Gatekeeper opens them without a
warning. Each release also has a `.sha256` file for the zip:

```bash
shasum -a 256 -c OhMyTweetDeck-<version>-macos.zip.sha256
```

Requires macOS 14+ on Apple Silicon.

## Requirements

- macOS 14+, Xcode 16+ (Swift 6 toolchain)
- Threads: a Meta app with `threads_basic` + `threads_content_publish`, your Threads user ID
  and an access token. Until the app has advanced access, it can post only for Threads testers
  added to the app, which includes yourself.
- Instagram: a professional (Business/Creator) account, an app with
  `instagram_business_basic` + `instagram_business_content_publish`, the account ID and a token.

## Build and run

```bash
swift test                    # core logic tests (no network)
scripts/build-app.sh          # → build/OhMyTweetDeck.app (ad-hoc signed)
open build/OhMyTweetDeck.app
```

Always run from the `.app`: its fixed bundle id (`dev.unohee.OhMyTweetDeck`) scopes your web
logins and Keychain items. `swift run` works for quick UI checks but uses a different identity.

### Signing and releases

`scripts/build-app.sh` signs ad-hoc by default, which is enough for local development. Set
`OMT_SIGN_ID` to sign with a Developer ID identity instead, with the hardened runtime and a
secure timestamp. Use an identity name or SHA-1 hash, or `auto`. `auto` lists the keychain's
"Developer ID Application" identities by SHA-1 hash, probe-signs a throwaway file with each and
uses the first that works, so a duplicate-named certificate or a CI keychain that shadows the
key cannot break a release:

```bash
OMT_SIGN_ID=auto scripts/build-app.sh release   # Developer ID signed bundle
scripts/notarize.sh                             # notarize, staple, write build/*.zip + .sha256
scripts/release.sh                              # build, notarize and publish the GitHub Release
```

`scripts/notarize.sh` uses a `notarytool` keychain profile (`OMT_NOTARY_PROFILE`, default
`intrect`). `scripts/release.sh` reads the version from `Resources/Info.plist`. It publishes
`v<version>` with the zip and its checksum. If that release already has both files, it does
nothing, and it never replaces or deletes an existing release.

## Using it

- **Add column**: toolbar `+` → pick a preset, or "Custom path…" for any page on the service
  (a profile, list, or `/search?q=…&f=live`).
- **Column menu (…)**: go home, move left/right, width, remove. The layout is saved to
  `~/Library/Application Support/dev.unohee.OhMyTweetDeck/columns.json`.
- **Auto-refresh**: toolbar clock menu → Off, or every 1/2/5/10/15 min (default 5). A column
  reloads only when it is idle: on its home page, near the top, nothing typed or focused, no
  dialog open and nothing playing with sound. A busy column is checked again 30 s later.
  "Refresh all now" in the same menu reloads every column at once, skipping those checks. For a quick test:
  `build/OhMyTweetDeck.app/Contents/MacOS/OhMyTweetDeck -autoRefreshSeconds 60`; decisions are
  logged under the `auto-refresh` category (`log stream --level debug --predicate 'category == "auto-refresh"'`).
- **Compose** (⌘N toggles, ⌘↩ posts): pick targets; each shows its remaining length in that
  service's own counting (X weighted: CJK/emoji = 2, URL = 23; Threads: emoji = UTF-8 bytes).
- **Accounts…** (⌘,): Threads and Instagram credentials.

## Layout

```
Sources/OhMyTweetDeckCore/   UI-free logic, unit-tested
  Service.swift              services, origins, feed presets, limits
  Column.swift               column model + JSON store
  TextMetrics.swift          per-service length counting
  PostDraft.swift            draft + per-service validation
  HTTP.swift                 transport seam + Graph API client
  Publishers.swift           Threads / Instagram publishers, X web intent, CrossPoster
  Credentials.swift          Keychain credential store
Sources/OhMyTweetDeck/       SwiftUI + WKWebView app
Tests/OhMyTweetDeckCoreTests/
scripts/build-app.sh         wraps the SwiftPM binary into a .app
scripts/notarize.sh          notarizes, staples and zips the Developer ID build
scripts/release.sh           publishes the GitHub Release for the Info.plist version
```

## Status and limits (v0.1)

- X posting drives x.com's page. The send-button selectors (`data-testid="tweetButton"`)
  come from x.com's DOM and can change. If the button is not found, the sheet asks you to
  press Post yourself, and "Mark as posted" records the result. Images are not sent to X.
- Instagram and Threads image posts need an image already hosted at a public URL. The app
  does not upload or host local files yet.
- Threads/Instagram tokens are pasted manually; there is no OAuth flow or token refresh yet.
- Sign-in buttons that open a popup window (Google, Apple, Facebook) may not complete inside a
  column; use the site's own username/password login.
- Local builds are ad-hoc signed unless `OMT_SIGN_ID` is set. An ad-hoc identity changes with
  each rebuild, so macOS may ask again before such a build reads its Keychain items. Release
  builds (Developer ID) keep a stable identity.
- No license has been chosen yet.
