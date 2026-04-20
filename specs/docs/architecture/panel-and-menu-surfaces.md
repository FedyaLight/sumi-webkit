# Panel and menu surfaces

This document freezes Aura's single-toolbar surface taxonomy, anchor rules, and
shared visual system for popovers, menus, and transient panels.

## Surface taxonomy

Aura uses exactly three surface kinds:

- `context menu`
- `popover panel`
- `persistent transient surface`

Definitions:

- `context menu`
  - small action list anchored to a local target
  - pointer-first, keyboard-accessible
  - not restored
- `popover panel`
  - bounded anchored surface with richer content
  - may contain sections, cards, or settings
  - not restored
- `persistent transient surface`
  - keyboard- or interaction-driven overlay that can remain open during a short
    task
  - not restored

## Surface mapping

- unified hub: `popover panel`
- site-controls panel: `popover panel`
- theme editor: `popover panel`
- Ctrl+Tab panel: `persistent transient surface`
- sidebar background menu: `context menu`
- space menu: `context menu`
- folder menu: `context menu`
- tab menu: `context menu`
- split item menu: `context menu`
- glance overlay controls: `persistent transient surface`
- media card menu: `context menu`

## Anchor rules

### Address-bar-adjacent

- unified hub anchors to the canonical address bar trailing cluster
- site-controls panel anchors to the site-controls button in that cluster
- site-controls-related surfaces must never anchor to page content

### Sidebar-anchored

- sidebar background menu anchors to empty sidebar background
- space menu anchors to the active space header row
- folder menu anchors to the target folder row
- tab menu anchors to the target tab or launcher row
- media card menu anchors to the target media card

### Centered transient

- Ctrl+Tab panel is center-aligned within the browser window
- it is not anchored to a specific tab row

### Theme editor

- theme editor anchors to the command that opened it
- it remains bounded and never becomes fullscreen by default
- if insufficient room exists, it may reposition but stays visually connected
  to its opener
- first-pass parity uses a bounded `380px` no-tail panel with `10px` internal
  padding, copied from Zen's current picker

## Shared visual rules

- one radius system:
  - context menus use `8px`
  - arrow panels use grounded Zen-like tokens:
    - width `380px` where explicitly required
    - `10px` radius on macOS
    - `12px` radius on macOS Tahoe
    - `5px` menu-item radius inside panel lists
- one elevation system:
  - elevated menu/panel surfaces use the shared shadow token family
  - arrow panels keep `8px` shadow margin where native rendering does not
    replace it
  - native macOS arrow popovers instead use `0px` CSS shadow margin and rely on
    OS shadowing
- one material policy:
  - native macOS arrow popovers stay transparent and do not add a second CSS
    shadow or opaque fill over the system material
  - non-native macOS popovers force a menu-like background instead of trying to
    fake NSPopover
  - expensive blur is opt-in per surface and must justify cost
  - blur is never the only affordance separating a surface from the background
- one padding grid:
  - compact menu row padding uses grounded Zen-like values:
    - `8px` block
    - `14px` inline
    - `4px` inline margin
    - `2px` block margin
  - panel body padding defaults to `2px 0`
  - footer buttons use a heavier grounded family:
    - `20px` block
    - `15px` inline
  - regular panel section padding may specialize from a grounded family:
    - permission-section padding `8px` block and `16px` inline
    - permission-row padding `4px` block
  - card padding for richer panels
- one timing policy:
  - fast hover affordances
  - immediate pressed feedback
  - no long easing on simple menu open or close

## Single-toolbar v1 decisions

- only the single-toolbar anchor geometry is frozen now
- no separate menu geometry is defined for multi-toolbar or collapsed-toolbar
  variants
- v1 overflow behavior is only:
  - inline pinned extension icons in the address bar
  - non-pinned extension actions overflowing below the address bar

## Surface stability rules

- menus and panels must not drift as the sidebar tree reflows
- unified hub and theme editor must remain clipped inside the window bounds
- unified site-controls panel must keep its header, add-ons, settings, and
  footer section order even while rows appear or disappear
- app menu and other tall panels must constrain to available screen height and
  never silently clip
- Ctrl+Tab panel never restores after restart
- panel open and close must not mutate durable shell state directly
- all committed actions route through canonical owners, not surface-local hacks

## macOS popover rules

- native arrow popovers and non-native popovers are distinct surface cases
- bounded no-tail popovers are valid and required for the theme picker
- Aura must explicitly model Zen's `hidepopovertail` and `nonnativepopover`
  behavior instead of leaving native-vs-nonnative decisions implicit
- Aura must keep explicit control over when a panel prefers native macOS
  popover behavior and when it forces a non-native rendering path
- native macOS popovers must not accumulate a second CSS shadow, border, or
  opaque background layer on top of the OS material
- non-native macOS popovers must intentionally render as menu-like surfaces
  rather than looking like a broken native popover

## Performance guardrails

- no second layout system for panels
- no per-surface polling for anchor changes
- no heavy blur stacks on hot-path ephemeral menus
- anchor recomputation must be event-driven and local to the owning surface
