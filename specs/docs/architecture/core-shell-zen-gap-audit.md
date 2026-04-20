# Core shell Zen gap audit

This file tracks the remaining differences and under-specified scenarios found
while comparing Aura's frozen core shell spec to Zen's documented behavior and
release history.

## High-confidence gaps now covered in the frozen spec

- per-space pinned section is now explicit
- split view is capped at four visible items
- split content-area controls are explicit
- `Split Link in New Tab` is explicit
- glance default behavior for pinned and essentials is explicit
- profile-based space routing is now called out as an intentional divergence
- canonical address bar, compact mode, and keyboard semantics are now frozen in
  a dedicated shell doc
- release-note-derived anti-regression scenarios are now tracked explicitly
- single-toolbar sidebar density and panel/menu surface rules are now frozen in
  dedicated visual docs
- live Zen theme picker behavior is now frozen in dedicated parity docs
- Zen test-grounded compact, popover, folder-density, and floating-urlbar
  behaviors are now frozen explicitly

## Remaining lower-confidence gaps

### Advanced toolbar permutations

- the exact interaction matrix for future multi-toolbar variants if Aura ever
  expands beyond the current canonical single-sidebar shell
- whether every Zen compact-mode preference should become a first-class Aura
  setting or remain an advanced preference

### Glance edge cases

- split plus glance coexistence while the parent tab already lives inside a
  nested split
- the exact full internal-page bypass matrix beyond the grounded
  `http/https/file` allowlist

### Future-only behavior

- Zen multi-window sync behavior
- full live folder interaction semantics
- settings UI for shortcut rebinding and advanced compact preferences
- onboarding and non-shell settings flows outside customization import/export

## Why this file exists

The core shell spec is already strong enough for implementation to start, but
these gaps are exactly the kind that later turn into subtle behavior regressions
if they are left implicit.
