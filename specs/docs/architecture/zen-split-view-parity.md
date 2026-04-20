# Zen split-view parity

This document freezes the first implementation-complete split-view contract for
Aura against the live Zen sources and the current Helium split host.

Aura must preserve Zen's user-facing split behavior `1:1` while using cleaner
and more maintainable internals on top of Helium's native desktop runtime.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/ZenViewSplitter.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/zen-split-view.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/zen-split-group.inc.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/zen-splitview-overlay.inc.xhtml`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/base/content/zen-commands.inc.xhtml`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/base/content/nsContextMenu-sys-mjs.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/drag-and-drop-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabbrowser-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/sessionstore/SessionStore-sys-mjs.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/sessionstore/TabGroupState-sys-mjs.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_basic_split_view.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_browser_duplication.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_groups.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_inset_checks.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_empty.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_folders.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_glance.js`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view.h`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view.cc`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view_delegate.h`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view_drop_target_controller.h`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view_drop_target_controller.cc`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view_mini_toolbar.h`
- `/Users/fedaefimov/Downloads/Aura/upstream/helium-macos/build/src/chrome/browser/ui/views/frame/multi_contents_view_mini_toolbar.cc`

## Frozen Zen behavior

### Commands and entrypoints

- Zen exposes first-class split commands for:
  - `grid`
  - `vertical`
  - `horizontal`
  - `unsplit`
  - `Split Link in New Tab`
  - `New Empty Split`
- Aura keeps the same command surface and command ownership.
- `Split Link in New Tab` appears only for real link targets and stays hidden
  for `mailto:` and `tel:` targets.

### Context menu behavior

- Zen injects `Split Tabs` immediately before the upstream
  `Move Tab To Split View` row.
- the same row becomes `Un-split Tabs` if any selected tab is already inside a
  split
- `Split Tabs` is shown only when:
  - there are `2..4` selected tabs
  - no selected tab is already in split
  - no selected tab is the empty split replacement tab
- Aura must keep this exact menu gating and relative menu position.

### Split capacity and layout

- max visible split members is `4`
- supported layout presets are:
  - `grid`
  - `vertical`
  - `horizontal`
- Zen persists a split `layoutTree`, not just a flat list
- split insertion can:
  - append into an existing compatible axis node
  - wrap an existing node with a new parent when the requested side changes axis
- Aura must preserve this tree behavior, not flatten it into index shuffles.

### Drag and drop

- dragging a tab to the content host edges exposes split targets
- dragging a tab over another tab for `300ms` exposes split-on-tab behavior
- dropping a split member on another split member can:
  - swap nodes when appropriate
  - move within the same split tree
  - wrap the target node in a new parent
- dropping a tab on itself at a valid side creates an empty split placeholder
  path in Zen
- drag-over-split is explicitly narrower than command split:
  - it rejects Essentials
  - it rejects live glance child tabs as targets
  - it rejects existing split groups as drag-over-split targets
  - it rejects live-folder-backed tabs
  - it rejects multi-select drags
- Aura must preserve the visible behavior, but must not recreate Zen's
  synthetic empty-tab internals

### Hover controls in active split

- the active split content shows a hover header toolbar
- that toolbar contains:
  - `rearrange`
  - `unsplit`
- controls are hover-revealed and do not permanently consume layout space
- active split content shows a visible outline
- Aura must treat this hover header as part of split parity, not as optional
  polish

### Duplication and propagation rules

- `normal + pinned` duplicates the pinned side into an unpinned split group and
  leaves the original pinned tab outside the group
- `pinned + pinned` creates no duplicates and the split group remains pinned
- `pinned + essential` duplicates and keeps both original launcher-backed tabs
  outside the split group
- `essential + essential` duplicates and does not create an essentials-owned
  split group
- live-folder-backed tabs follow the same duplication-protection path as pinned
  or essential-backed tabs
- pinning any member of a split group pins the entire group
- unpinning any member unpins the entire group
- a split created from folder tabs preserves the folder parent linkage
- split groups render as a grouped sidebar unit rather than flattening into
  unrelated standalone rows
- split groups are non-collapsible in the sidebar
- moving one member of a split group to another space moves the entire split
  group

### Empty split and restore behavior

- `New Empty Split` exists as a first-class action
- the empty split affordance is a temporary runtime surface and must not leak
  into durable tab identity, traversal, or restore
- Aura persists `layoutTree` as the sole split-restore source of truth;
  projected flat split items are rebuilt from that tree instead of competing
  with it during restore
- restart restores valid split layout trees and drops invalid layouts cleanly
- unsplitting the last remaining member removes the split group from the DOM and
  runtime model

## Helium host translation strategy

Helium already provides a native split host, but its visible UI is narrower
than Zen's current split system.

### What Aura reuses directly

- `MultiContentsView` as the real content host
- `MultiContentsViewDropTargetController` as the native drag-entry seam
- `MultiContentsViewDelegateImpl` as the runtime bridge for:
  - tab drops
  - link drops
  - resize
  - swap
- `BrowserView` split plumbing as the only content-runtime owner

### What Aura must own on top

- split layout tree with up to `4` visible members
- Zen-style split preset commands and context menu behavior
- split duplication policy for pinned, essential, and live-folder-backed tabs
- hover header controls for:
  - rearrange
  - unsplit
- active split outline and split-group menu semantics
- empty split runtime surface that replaces Zen's synthetic empty-tab approach

### What Aura must not do

- do not invent a second content runtime
- do not poll split hover or resize state
- do not copy Zen's placeholder-tab or `owned-tabs-in-folder` internals
- do not collapse Zen's split tree into a flat two-pane-only mental model

## Aura contracts required for parity

- one Aura-owned split layout model with a persisted layout tree
- one Aura-owned split projection/controller that can drive Helium's host
- one split menu and command owner shared by:
  - context menu
  - link context menu
  - hover header commands
  - keyboard commands
- one split DnD engine shared with the rest of Aura's interaction engine

## Runtime-only gaps that still need live wiring

- actual Helium mounting of the hover header over split contents
- exact mapping from Aura's `4`-member tree model onto Helium's current
  `MultiContentsView` host
- live menu-row rendering and icons in the real tab context menu
- pixel polish of the active outline, inset spacing, and hover fade timing
