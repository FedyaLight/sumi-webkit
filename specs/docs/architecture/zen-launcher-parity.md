# Zen launcher parity

This document freezes the grounded Zen behavior for launcher-backed rows and the
small Aura-owned extension we are adding on top.

## What Zen actually does

- the changed-url affordance is implemented in
  `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tabs/ZenPinnedTabManager.mjs`
  and applies to pinned launcher-backed tabs only
- `Essentials` are explicitly excluded from that path
- when the live pinned tab leaves its stored launcher URL, Zen marks it with
  `zen-pinned-changed`
- the row then:
  - keeps the live page title
  - shows a slash-like separator before that title
  - repurposes the icon area into a reset button
- the reset button sends the pinned launcher back to its stored launcher URL
  and selects it if needed
- `Ctrl` or `Cmd` on the reset button duplicates the changed live page into a
  regular unpinned tab before resetting the launcher

## Important source details

- Zen's current code compares launcher divergence after stripping hash
  fragments only
- the source comment mentions query params too, but the implementation does not
  currently strip `?`
- grouped pinned launchers preserve this changed-url state through
  `had-zen-pinned-changed` while they temporarily live inside split or folder
  grouping

## Context menu grounding

- Zen exposes `Replace Pinned URL with Current` for changed pinned launchers
- Zen exposes `Edit Title`
- Zen exposes `Edit Icon`
- `Edit Title` is hidden for Essentials
- `Edit Icon` uses the Zen emoji picker with SVG support
- Zen does not expose a generic `Edit Link` row for launcher-backed entries

## Icon support grounding

- launcher-backed rows can override their icon through the same emoji or SVG
  picker family Zen uses elsewhere
- folders can override their icon
- spaces can override their icon
- Aura should treat launcher, folder, and space icon override persistence as
  one consistent model

## Aura decisions

- Aura copies the changed pinned-launcher affordance exactly:
  - pinned only
  - not Essentials
  - slash marker before the live title
  - icon becomes reset-to-launcher action
- Aura persists launcher icon overrides as `iconAsset`
- Aura adds `Edit Link` for launcher-backed rows as an Aura-owned extension so
  the launcher URL can be edited directly instead of only replaced from the
  current page
