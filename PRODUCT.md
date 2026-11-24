# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (SwiftUI + WKWebView, SwiftPM). Not one of the schema's four values: treat Apple
HIG conventions (as in ios.md: system controls, SF Symbols, system materials, semantic colors, Dark
Mode first-class) as the governing platform reference, adapted to a desktop window.

## Users

The owner of the app: a long-time TweetDeck power user who misses keeping several streams open
side by side. Primary scene: the app lives all day on a secondary monitor as an ambient monitoring
surface; posting happens occasionally, in short bursts.

## Product Purpose

Watch X, Threads and Instagram feeds simultaneously in TweetDeck-style columns, and send one
message to all of them from one composer. Success: glanceable parallel streams that never need
attention to stay useful, and a cross-post that reports per-service results honestly.

## Positioning

The classic TweetDeck model (columns + left compose rail) applied across today's three networks at
once, as a native Mac app rather than a browser tab.

## Operating Context

- Columns are the real third-party websites (x.com, threads.com, instagram.com) in web views. Their
  content is outside the app's design control.
- Posting: Threads and Instagram through official APIs (Keychain credentials); X through the user's
  logged-in x.com intent composer shown in a sheet.
- Instagram requires a public image URL per post; X receives text only.

## Capabilities and Constraints

- Design scope is the app chrome only: window, toolbar, column headers, compose rail, sheets,
  settings, posting feedback. No CSS injected into the web columns (confirmed 2026-11-24).
- Columns: add from presets or a custom path, reorder, resize width, remove; layout persists.
- Per-service length counters and validation; per-service outcomes after posting.
- Undecided: license; OAuth sign-in for Threads/Instagram; local image upload.

## Brand Commitments

- Name: "Oh My TweetDeck".
- User-pinned aesthetic (2026-11-24): the feel of the original 2011–2014 TweetDeck, rendered in
  today's macOS Liquid Glass. This is the binding visual brief for the chrome.

## Evidence on Hand

- Working app and screenshot of the first build (three columns + compose rail).
- No logos or brand assets yet. Do not imitate X/Twitter, Meta or TweetDeck trademarks or logos.

## Product Principles

1. The streams are the content; chrome stays out of their way and never competes with them.
2. Readable at a glance from across a desk, all day, without fatigue.
3. Honest posting: every target gets an explicit result; nothing is assumed sent.
4. Native first: system controls and materials, no web-shaped widgets.

## Accessibility & Inclusion

Respect Reduce Transparency, Increase Contrast and Reduce Motion: Liquid Glass surfaces must fall
back to solid, legible materials when those settings are on.
