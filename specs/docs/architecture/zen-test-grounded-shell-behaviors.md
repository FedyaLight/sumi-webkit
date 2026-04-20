# Zen test-grounded shell behaviors

This document freezes Aura behaviors that are strong enough to lift directly
from Zen's own tests before the first native implementation lands.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/popover/browser_popover_height_constraint.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/compact_mode/browser_compact_mode_width.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_density.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_visible_tabs.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_max_subfolders.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/spaces/browser_overflow_scrollbox.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/urlbar/browser_floating_urlbar.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/urlbar/browser_issue_7385.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_browser_duplication.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_folders.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_select_parent.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_next_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_prev_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_expand.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_glance.js`

## Frozen behavior

- compact mode width must preserve the original sidebar or titlebar width on
  left-side, right-side, and hover-reveal paths
- app menu and similar tall popovers must constrain to available screen height
  instead of silently clipping
- folder rows must match tab rows in height and width across density changes
- overflowing sidebar sections must auto-scroll the selected item into view
- keyboard-triggered open-location may use the floating URL bar presentation
- click-triggered URL bar focus must not force floating URL bar mode
- floating URL bar must still select the full value when opened through the
  keyboard-triggered path
- wrap-around workspace navigation defaults to enabled
- closing the last unpinned tab defaults to no forced replacement tab
- a selected tab inside a collapsed folder remains visible as the active folder
  projection
- a previously selected tab may remain projected after selection leaves the
  folder until projection is explicitly reset
- nested subfolders disable further creation at depth `5`
- selecting the parent of a live glance must reselect the live glance child
- next or previous tab traversal from a live glance must use the
  parent-adjacent ordering
- expanding a glance must place it immediately after the parent, or as the
  first normal visible tab when the parent is pinned
- expanding a glance out of split must remove glance-only state without leaving
  the promoted tab inside the old split group
- the glance split command disables when the current split already has `4`
  visible members
- split duplication keeps these Zen rules:
  - normal + pinned duplicates only the normal side into the split group
  - pinned + pinned stays pinned and does not create duplicate tabs
  - pinned + essential does not absorb the essential into a split group
  - essential + essential does not create an essentials split group
- split groups created from folder tabs retain folder parent linkage after
  duplication
- split pin and unpin propagate to the whole group
- unsplitting the final member removes the split group cleanly
- split inset geometry must remain stable across:
  - basic split
  - horizontal split
  - `3`-item grid split

## Why Aura freezes these now

These are the kinds of bugs that often reappear during native rewrites:

- geometry drift
- clipped popovers
- density mismatch
- selected-item invisibility inside overflow regions
- keyboard-vs-pointer URL bar inconsistencies

Aura treats them as first-class acceptance criteria, not later polish.
