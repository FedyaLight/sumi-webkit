# Zen GitHub issues scenario audit

This document records the user-facing Zen issue patterns extracted from:

- `/Users/fedaefimov/Downloads/deep-research-report (1).md`

The report is not a canonical source of Zen behavior. It is a source of
failure scenarios. Aura uses it to capture:

- regressions that should become explicit acceptance tests
- Zen bug clusters that should not be copied into Aura's architecture
- Firefox, Gecko, packaging, or platform bugs that should not be mistaken for
  Aura shell parity requirements

## High-signal Aura shell regressions to freeze

The following issue clusters are directly relevant to Aura's shell behavior and
should be treated as anti-regression scenarios:

- URL bar popup anchoring can drift or become misplaced during new-tab or
  floating paths.
- URL bar focus and editing can degrade:
  - text becomes hard to select
  - the bar stays visible when it should hide
  - current-tab and current-URL results are not ranked above weaker matches
- Essentials and tabs can be too easy to drag accidentally.
- Essentials can reopen in a jumbled order if restore identity is not stable.
- split preview or highlight residue can remain visible after `Escape`.
- opening a tab from an external app while workspace or space routing is active
  can deadlock or freeze the shell.
- compact-mode reveal can stop working after snapped or tiled window geometry
  changes.
- extension keyboard shortcuts can be swallowed when the sidebar is collapsed or
  compact.

Aura freezes these as real anti-regression cases because they map to the first
native shell rewrite and do not depend on Firefox-only internals.

## Scenarios to adopt as explicit Aura requirements

- URL bar results and popovers must stay anchored to the canonical address bar
  cluster in both click-opened and keyboard-opened paths.
- URL bar editing must remain a normal text-editing field:
  - selection works
  - copy and replace work
  - floating mode does not create a non-editable or non-selectable state
- active-tab and current-URL relevance must be ranked ahead of generic matches
  when Zen's learner and action catalog would surface them.
- drag requires explicit slop and intent before a tab or Essential can enter a
  move path.
- Essentials order must survive reopen, restore, and detach-or-return flows
  without slot jumbling.
- split preview must have a deterministic teardown path for `Escape`,
  cancellation, and focus loss.
- external-open tab routing must use the same space, profile, and shell
  transaction owner as ordinary tab creation.
- compact reveal must remain legal and visible under snapped or tiled window
  geometry.
- shell-level compact or collapsed states must not intercept extension keyboard
  shortcuts.

## Useful signals, but deferred or outside first-pass scope

Some issue clusters are useful warnings, but they do not become first-pass Aura
requirements as-is:

- cross-window workspace corruption
- inactive-window theme update drift
- compact mode on non-primary windows

Aura is explicitly `single-window-first`, so these remain future-window risks
rather than v1 parity blockers.

The same is true for fullscreen bookmarks-bar behavior: it is a browser-chrome
visibility policy concern, but not a first-pass Aura-owned shell feature unless
the bookmarks bar itself becomes part of the frozen rewrite scope.

## Host-runtime or Firefox-specific issues not to confuse with shell parity

The report also includes bugs that should not be copied into Aura's parity
model because they are largely Gecko, packaging, or platform concerns:

- Wayland plus VA-API media playback crashes
- default-browser `xdg-open` and Flatpak launch failures
- stale profile lock files after shutdown
- Linux-only site audio failures unrelated to shell media cards
- extension-specific autofill failures that do not stem from Aura shell routing

These issues still matter for product quality, but they do not define how Aura
should model split, glance, spaces, folders, menus, or theme behavior.

## Concrete Aura guidance

- Treat GitHub issue patterns as regression prompts, not as direct behavior
  truth.
- Promote shell-relevant issue clusters into the acceptance matrix and smoke
  checklist.
- Keep Firefox, packaging, and platform bugs documented separately from Aura
  shell parity.
- Where Zen issue evidence conflicts with Aura's current deliberate scope, keep
  Aura's explicit architectural rules rather than inheriting Zen's older
  cross-window complexity.
