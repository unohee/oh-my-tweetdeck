# CLAUDE.md — oh-my-tweetdeck

TweetDeck-style macOS app: X / Threads / Instagram web columns + one composer that
cross-posts. SwiftPM package (no Xcode project). Read README.md first.

## Commands

- `swift build` / `swift test` — core tests are pure (scripted HTTP transport, no network).
- `scripts/build-app.sh [debug|release]` → `build/OhMyTweetDeck.app`. Run the app from the bundle.

## Rules

- **Never send a real post during development or tests.** These are the user's live accounts.
  Test publishers with `ScriptedTransport`; for the X sheet, verify up to (not including) Post.
- Keep `OhMyTweetDeckCore` free of AppKit/SwiftUI/WebKit so it stays unit-testable.
- Tokens go in the Keychain (`KeychainCredentialStore`) and the `Authorization` header — never
  in files, logs or URLs.
- X posting must go through x.com's own page (intent composer). Do not call X's private GraphQL
  directly: it needs a signed `x-client-transaction-id` (OldTweetDeck relies on a third-party
  solver iframe for it).
- Do not vendor OldTweetDeck's TweetDeck bundle (`vendor.js`/`bundle.js`). That code belongs to X, not to OldTweetDeck's MIT license.
- Before changing Graph API calls, re-read the official docs (host/version/params change):
  Threads `graph.threads.com/v1.0`, Instagram `graph.instagram.com/v23.0`.
- Web selectors/paths (X send button, feed preset paths) come from live sites and rot; treat
  "not found" as a supported state, not a crash.
- Experiments: `testing/{name}_{YYMMDD}_{ver}.swift`. Deletions go to `trash/`.
