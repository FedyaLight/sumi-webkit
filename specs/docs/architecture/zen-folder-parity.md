# Zen folder parity

This document freezes the user-visible folder behavior Aura should copy from the
local Zen source without inheriting Zen's internal placeholder-tab hacks.

## Grounding

Grounded against:

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/folders/ZenFolder.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/folders/ZenFolders.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/folders/zen-folders.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_basic_toggle.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_visible_tabs.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_density.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_reset_button.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/folders/browser_folder_max_subfolders.js`

## What a folder is

For Aura's clean model, a folder is:

- a first-class sidebar tree node
- a way to organize regular launchers and regular tab-backed entries
- not a different launcher type

Launchers inside a folder keep their normal semantics:

- same activation rules
- same URL or reset behavior
- same restore identity

The folder adds:

- hierarchy
- collapse and expand behavior
- active-child projection behavior
- optional folder icon metadata

## What Aura intentionally does not copy

Zen currently relies on Firefox tab-group internals and special rules such as:

- a synthetic `zen-empty-tab`
- optional `owned-tabs-in-folder`
- pinned-tab plumbing for folder membership

Aura does not copy these internals. It copies the user-visible behavior.

## Folder icon parity

Zen folder icons are not separate badges outside the folder row.

Aura must treat the folder icon like Zen does:

- the icon lives inside the folder shell itself
- it is rendered inside the folder SVG, not as a trailing chip
- `Change Folder Icon` edits this first-class folder property
- removing the user icon falls back to the default folder glyph state

Aura persists this as `folderIconAsset` on the folder entry.

## Folder icon visual states

The Zen folder icon has two orthogonal state axes:

- open vs closed
- custom icon vs dots indicator when active projection exists

Aura should preserve the same visible logic:

- default closed folder: front and back folder glyph at rest
- open folder: folder shell shifts into the open state
- custom icon visible when the folder is not showing active-projection dots
- when a collapsed folder has active projection, the custom icon hides and the
  internal dots state becomes visible

The custom icon still lives inside the folder shell; it does not migrate
outside the folder row.

## Frozen motion rules

Zen currently animates folder visuals through state changes on the embedded SVG
and container height changes.

Aura should copy these behaviors:

- click toggles collapsed or expanded state
- collapse and expand animate cleanly without leaving empty gaps
- folder icon transitions are bounded and state-driven, not timer-loop-driven
- active-projection transitions should not leak observer graphs or layout
  thrash

Exact motion curves remain implementation-level, but the visible behaviors must
match Zen:

- shell open/close state changes with the folder
- icon and dots swap visibility based on active projection
- folder height animation stays aligned with tab density

Grounded current Zen timings and transitions:

- embedded folder SVG parts (`g`, `rect`, `path`) transition with:
  - duration `0.3s`
  - curve `cubic-bezier(0.42, 0, 0, 1)`
- collapsed-sidebar icon translate uses:
  - duration `0.1s`
  - curve `ease`
- folder collapse, expand, select, and unload margin or height choreography use
  bounded JS-driven animations around:
  - duration `0.12s`
  - curve `easeInOut`

## Active projection and reset

Zen keeps a selected child visible when its folder is collapsed.

Aura copies that behavior:

- a selected child inside a collapsed folder remains projected
- a previously active child may remain projected until reset
- reset clears the folder-active projection state

## Depth and density

- nested subfolders stop at depth `5`
- folder rows match tab rows in width and height
- indentation uses the same visual step as grounded Zen sidebar density
