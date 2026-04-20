# Zen release notes scenario audit

This document records high-confidence shell scenarios extracted from Zen's
release notes so Aura can encode them as requirements before implementation.

The goal is not to mirror every release note item. The goal is to capture the
user-visible interaction bugs and behavior corrections that repeatedly appeared
in Zen and would otherwise become subtle regressions in Aura.

## Address bar and command bar lessons

- the address bar can switch spaces by typing their names
- command actions must rank highly in address bar results
- `Tab` on an empty command bar should reveal all commands
- `Ctrl` or `Cmd` + `T` should close the open address bar if it is already in
  new-tab replacement mode
- blurring the window must not close the open address bar
- direct URL input should still offer explicit "search this text" fallback
- command bar fixes are common enough that address-bar action routing must stay
  centralized, typed, and regression-tested

These are frozen in:

- `core-shell-address-bar-compact-and-keyboard.md`
- `core-shell-acceptance-matrix.md`

## Compact mode lessons

- compact mode can become observation-heavy and expensive if implemented with
  too many watchers
- the address bar must not remain visually stuck after compact reveal hides
- compact mode and fullscreen should not show stray borders
- top buttons should not reserve dead space when empty
- split view and compact mode must coexist without broken layout
- compact-mode background and theme transitions should move with space
  switching, not after it
- compact mode must initialize correctly for new windows and private windows

These are frozen in:

- `core-shell-address-bar-compact-and-keyboard.md`
- `core-shell-interaction-model.md`

## Spaces, essentials, and pinned items

- switching spaces must not make essentials disappear
- pinned items must restore correctly across startup and session recovery
- pinned items must not lose their icons when unloaded or restored
- restoring tabs across spaces must preserve their space assignment
- space switching should be measurably performant, not just visually correct
- `Unload all spaces except current` is a first-class management action
- clicking reset on a pinned item should select it if needed
- modifier-activating a resettable pinned item should duplicate it to the
  background
- dragging a pinned item out of the window must not implicitly create a new
  window
- the active space header can act as the collapse toggle for pinned items

These are frozen in:

- `core-shell-overview.md`
- `core-shell-interaction-model.md`
- `core-shell-state-and-restore.md`

## Folders, drag and reorder

- drag and drop with nested folders can easily leave empty spaces if preview
  and commit are not separated
- sub-folders can separate from their parent after restore if tree identity is
  not canonical
- drag and drop should remain stable even when multiple folder layers are
  involved
- folder names and icons must persist cleanly across restart

These are frozen in:

- `core-shell-interaction-model.md`
- `core-shell-acceptance-matrix.md`
- `core-shell-state-and-restore.md`

## Split and glance

- dragging a tab over another tab with a `300ms` dwell should expose split
  affordance
- center-drop split should expose explicit top and bottom placement
- split layout and sizes must survive restart
- split view should hide chrome safely in fullscreen without destroying layout
- "Create new split" from command bar must route through the same split engine
- split context menus should expose un-split directly
- glance performance and animation quality matter enough to be called out in
  release notes, so glance must share the same performance budget discipline as
  split
- ctrl or shift link gestures must not accidentally suppress or trigger glance
- alt-select style interactions must not accidentally trigger glance
- split plus glance memory leaks are a known class of bug, so ownership and
  teardown must stay explicit

These are frozen in:

- `core-shell-interaction-model.md`
- `core-shell-menu-matrix.md`
- `core-shell-acceptance-matrix.md`

## Focus and keyboard

- closing a tab should prefer the last accessed tab over simple visual sibling
  order
- new macOS profiles should come with ready-to-use `switch to N space`
  shortcuts
- back and forward history shortcuts must not accidentally switch spaces
- blank window is its own window mode with dedicated shortcut behavior

These are frozen in:

- `core-shell-interaction-model.md`
- `core-shell-address-bar-compact-and-keyboard.md`

## Blank windows and startup behavior

- a blank window is distinct from the normal Aura shell and opens without the
  usual pinned or space context
- blank window mode intersects with restore and future window sync, so it
  cannot be faked as "just another space"
- first-launch and new-window flows must not accidentally collapse into the
  normal restored window path
- startup restore must remember the active space for normal windows

These are frozen in:

- `core-shell-state-and-restore.md`
- `implementation-roadmap.md`

## Panels and popovers

- popup inputs must autofocus reliably on macOS
- native popover adoption on macOS is a product-level quality signal
- Ctrl+Tab panel focus should be managed explicitly rather than trusting default
  autofocus
- icon pickers and similar editors should not close eagerly on simple
  selection

These are frozen in:

- `browser-chrome-pipeline.md`
- `workspace-theme-surface-model.md`

## Live folders and feed-driven UI

- live folders are a real Zen feature and not just a folder variant
- feed compatibility and GitHub or RSS fetching were real release-note issues
- Aura should keep live folders out of the first shell rewrite until it has a
  separate explicit service owner
- when Aura adopts live folders, it must be as a first-class feature, not as
  hidden behavior inside normal folders

These are frozen in:

- `implementation-roadmap.md`
- `core-shell-zen-gap-audit.md`

## Performance and maintainability lessons

- compact mode hover logic must be centralized and measurable
- folder or icon animations can leak or thrash if they are not bounded
- space switching performance matters enough to be a release-note-level
  concern, so Aura must treat it as a perf budget item, not polish
- theme background transitions should animate responsively during workspace
  switching
- media-controller-style UI should not introduce visible idle performance cost
- drag and drop between windows and split views must be treated as first-class
  regressions, not edge cleanup after launch
- popup and glance fixes recurring in release notes mean teardown and focus
  rules should live in one owner, not in view-local callbacks

These are frozen in:

- `docs/perf/budgets.md`
- `core-shell-address-bar-compact-and-keyboard.md`
- `core-shell-acceptance-matrix.md`
