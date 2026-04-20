# Compact Mode Legal State Matrix

Aura targets Zen parity for compact mode behavior, but the first native rewrite
ships only the legal single-toolbar path.

## V1 legal user-facing mode

For `single-toolbar / single-sidebar`, the only exposed compact path is:

- compact mode enabled
- sidebar hidden
- toolbar remains the canonical shell host

Aura does not expose Zen's `hide toolbar` or `hide both` submenu in this v1
surface.

## Centralized behavior

- popup tracking, hover tracking, and floating URL bar participation are owned
  by one controller
- revealed chrome stays open while hover or popup state is active
- default hover hide delay is `1000ms`
- default flash duration is `800ms`
- compact mode must not leave stuck hover, selection, or floating URL bar
  artifacts behind

## Illegal-state handling

Illegal states still need to be modeled even if the UI does not expose them:

- invalid restore combinations fall back to `hide sidebar`
- future multi-toolbar layouts may re-enable extra compact policies, but those
  policies must stay behind explicit layout checks
- single-toolbar compact mode must never silently drift into `hide toolbar` or
  `hide both`

## Performance rule

- compact mode is event-driven and centralized
- no polling loops
- no per-view hover controllers
- no separate compact implementation for menus, theme editor, or media cards
