# Zen split and glance sidebar parity

This note freezes the sidebar, workspace, and selection semantics that sit
between Zen split-view and Glance.

These behaviors are subtle, easy to regress, and not fully covered by a single
split or glance source file, so Aura keeps them explicit here.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabbrowser-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tabgroup-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/drag-and-drop-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/glance/ZenGlanceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/ZenViewSplitter.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/zen-split-group.inc.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/ZenSpaceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/folders/ZenFolders.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tabs/ZenPinnedTabManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_select_parent.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_next_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_prev_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_expand.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_glance.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_folders.js`

## Split groups in the sidebar

- split groups render as a dedicated grouped sidebar unit, not as unrelated
  independent tab rows
- the underlying Zen representation is a `tab-group[split-view-group]`
- split groups are non-collapsible in the sidebar
- split groups can live:
  - in the normal per-space tree
  - in the pinned section
  - inside a folder
- when a split group is moved between spaces, the move applies to the whole
  group, not just the clicked member
- when a split group is nested under a folder, the folder remains the sidebar
  parent of the group after duplication and restore

## Glance in the sidebar

- Glance is not represented as a normal standalone sidebar row
- Zen treats the live glance as parent-linked state and parent-adjacent
  affordance
- the live child is physically nested inside the parent row instead of being
  inserted as an independent Essentials or tab row
- in collapsed or Essentials-style rows this shows up as a trailing mini-chip
  on the parent row
- a live glance is excluded from the normal counts used for:
  - visible tab ordering
  - pinned counts
  - essentials counts
- selecting the parent row of a live glance reselects the live glance child
- next or previous traversal from a live glance uses parent-adjacent ordering
  instead of raw child placement

## Split plus Glance interaction

- opening Glance while a split is active preserves the split host without
  collapsing it
- switching away from a live glance closes the visible overlay path but keeps
  the parent-child linkage alive
- returning to the parent of that glance reopens the live glance child
- expanding a glance from inside split does not keep the promoted tab inside
  the old split group
- splitting a glance converts the preview into a normal split member and keeps
  the parent plus child pair together

## Space and profile movement

- moving a parent tab with a live glance to another workspace moves the glance
  child to the same workspace
- moving one member of a split group to another workspace moves the whole split
  group
- Essentials remain Aura-specific:
  - the profile-owned launcher stays outside split consumption
  - a live essential instance may participate in split only through duplication

## Essentials and pinned edge semantics

- a live glance must not start counting as an Essential or pinned item just
  because the parent is Essential-backed or pinned
- pinned and essentials insertion math must ignore live glance children
- expanding a glance from an Essential-backed parent creates a normal regular
  tab:
  - it is not pinned
  - it is not placed inside the Essentials container
- a split group pinned in the sidebar behaves as one pinned grouped unit rather
  than a set of separately pinned launcher rows

## Aura translation rules

- Aura must model split groups as first-class grouped sidebar entities
- Aura must model live Glance as parent-linked transient state, not as a normal
  persisted sidebar entry
- Aura must keep selection and numbering calculations glance-aware
- Aura must move split groups and parent-linked glance state through one shell
  policy path instead of ad hoc per-view behavior

## Remaining runtime-only validation

- Aura still needs a live Helium parity pass for pixel polish around the nested
  glance child affordance on Essentials rows, but the behavioral placement
  rules are now source-grounded.
