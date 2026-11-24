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

## Using it

- **Add column**: toolbar `+` → pick a preset, or "Custom path…" for any page on the service
  (a profile, list, or `/search?q=…&f=live`).
- **Column menu (…)**: go home, move left/right, width, remove. The layout is saved to
  `~/Library/Application Support/dev.unohee.OhMyTweetDeck/columns.json`.
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
- Ad-hoc signed: after each rebuild macOS may ask again before the app reads its Keychain items.
- No license has been chosen yet.
