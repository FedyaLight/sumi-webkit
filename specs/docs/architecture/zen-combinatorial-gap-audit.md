# Zen combinatorial parity and gap audit

This document tracks the highest-risk combination scenarios across `split`,
`Glance`, `Essentials`, `pinned`, `folders`, DnD, and workspace switching.

Its purpose is to separate:

- combinations directly grounded in Zen code or tests
- combinations only partially grounded
- combinations where Zen itself has a gap, TODO, or inconsistent path that
  Aura must resolve explicitly

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/glance/ZenGlanceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/ZenViewSplitter.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/drag-and-drop/ZenDragAndDrop.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/ZenSpaceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/folders/ZenFolders.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tabs/ZenPinnedTabManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/sessionstore/ZenWindowSync.sys.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tab-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabs-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabbrowser-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/drag-and-drop-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabgroup-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_expand.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_select_parent.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_browser_duplication.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_groups.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_folders.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_glance.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/container_essentials/browser_container_specific_essentials.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_empty_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_owner_tabs.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_visible_tabs.js`

## Strongly grounded combinations

### Split plus regular tabs

- regular + regular split is grounded
- split groups are real grouped sidebar units
- pin and unpin propagate across the full split group
- unsplitting the last member removes the split group cleanly

### Split plus pinned tabs

- `normal + pinned` duplicates the pinned-backed side into a normal split group
- `pinned + pinned` stays pinned and creates no duplicate tabs
- a pinned split group remains one grouped pinned unit in the sidebar

### Split plus folders

- split created from folder tabs preserves the folder parent linkage
- folder active-projection logic explicitly special-cases split groups
- split groups can sit inside a folder and stay associated with that folder

### Glance plus regular tabs

- live glance is parent-linked
- switching away closes only the overlay surface and preserves linkage
- selecting the parent row reselects the live glance child
- expanding glance removes `zen-glance-tab` state and creates a normal tab

### Glance plus split

- live glance can open while split is active without crashing split state
- `Split Glance` converts the preview into a normal split member
- expanding glance from split removes glance-only state and keeps the original
  split group intact
- `Split Glance` disables when split capacity is already full

### Glance plus Essentials

- live glance from an Essential-backed parent is rendered as a nested child
  affordance inside the parent row
- the glance child does not become a standalone Essential item
- expanding the glance creates a normal regular tab:
  - not pinned
  - not placed inside the Essentials container

### Workspace movement

- `moveTabToWorkspace` explicitly mirrors workspace id from parent to live
  glance child
- moving one member of a split group between workspaces moves the whole split
  group
- Zen container-specific Essentials can be hidden or shown per workspace based
  on container identity

## Explicit Zen gaps or contradictions

### Essentials plus split are not fully coherent in Zen

- command-driven split has tests for:
  - `pinned + essential`
  - `essential + essential`
- those paths duplicate tabs and preserve the original launcher-backed tabs
  outside the split group
- but Zen's drag-over-split path explicitly blocks Essentials:
  - dropping onto an Essential row is rejected
  - dragging an Essential row into drag-over-split is rejected
- Zen also carries a direct `TODO` in `ZenViewSplitter` about split support for
  Essentials

This means Zen does not provide one coherent canonical answer for
`Essential <-> split via DnD`.

### Drag-over-split is narrower than it first appears

Zen drag-over-split currently rejects:

- Essentials as dragged items
- Essentials as drop targets
- live glance child tabs as drop targets
- existing split-group members as drag-over-split targets
- dragged split groups
- live-folder-backed tabs
- multi-selection drags

So the live Zen code only grounds tab-on-tab split DnD for a narrower subset of
regular tab cases.

### DnD workspace-switch and live glance propagation are not equally grounded

- Zen's normal `moveTabToWorkspace` helper explicitly mirrors workspace id onto
  the nested live glance child
- but `ZenDragAndDrop.#handle_dropSwitchSpace` manually rewrites
  `zen-workspace-id` on `movingTabs` and does not explicitly mirror nested
  glance children

Aura should treat this as a likely bug or at least a not-fully-grounded path in
Zen, not as a settled invariant.

### Split groups plus live glance during DnD workspace switch are even less grounded

- if a split-group member owns a live glance child, Zen's DnD switch-space path
  still appears to reason in terms of moved tabs or group members only
- there is no direct test proving the nested glance child always follows during
  the drag-induced workspace-switch path

### Folders still depend on Zen-only internals

Zen folder behavior still uses:

- `zen-empty-tab`
- optional `owned-tabs-in-folder`
- active-folder projections tied to group state

The user-visible behavior is useful, but the internal model is not a clean
foundation to copy directly into Aura.

## High-risk ungrounded or lightly grounded combinations

- DnD split from a live Essential instance
- DnD split onto an Essential-backed row
- DnD workspace-switch for parent + live glance child
- DnD workspace-switch for split group containing a member with live glance
- split group reordering across spaces while a folder projection is active
- split plus live-folder-backed tab plus folder projection
- multi-select plus drag-over-split
- container-specific Essential plus Glance plus workspace switch
- future profile-bound Aura spaces combined with any Zen container-specific
  Essential behavior

## Aura decisions required

Before native implementation claims `Zen parity`, Aura needs explicit contracts
for:

1. `Essential + split via DnD`
   Status: resolved Aura-owned rule.
   - the live essential instance may enter split
   - the Essentials slot stays reserved
   - unpinned split shows a split-proxy in the Essentials slot
   - pinning detaches the split permanently and restores the launcher
2. `live glance child propagation during drag-induced space switch`
3. `split group with nested live glance during drag-induced space switch`
4. `folder projection + split reparenting` without Zen placeholder internals
5. `profile-scoped Essentials with same-profile shared chrome` on top of Aura
   profile-bound spaces, because Zen's container-specific Essential behavior is
   not Aura's routing model

## Concrete guidance for Aura

- Treat command-driven split duplication rules as grounded.
- Treat drag-over-split support for Essentials as an Aura-owned extension, not a
  Zen-proven path.
- Treat live glance child propagation during DnD workspace switch as requiring
  dedicated acceptance tests.
- Do not port Zen's `zen-empty-tab` or `owned-tabs-in-folder` internals just to
  inherit these combination paths.
- Keep grouped split units and nested live glance children as first-class Aura
  model concepts so these combinations stay explicit and testable.
