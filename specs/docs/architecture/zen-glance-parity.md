# Zen glance parity

This document freezes Aura's `Glance` behavior directly from the downloaded Zen
sources. Aura keeps no intentional behavior divergence here; the only
product-level divergence remains `Essentials`.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/glance/ZenGlanceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/glance/zen-glance.inc.xhtml`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/glance/zen-glance.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/base/content/nsContextMenu-sys-mjs.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/kbs/ZenKeyboardShortcuts.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/split-view/ZenViewSplitter.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/ZenSpaceManager.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/components/tabbrowser/content/tab-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/toolkit/content/widgets/tabbox-js.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_basic.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_close.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_close_select.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_expand.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_next_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_prev_tab.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/glance/browser_glance_select_parent.js`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/tests/split_view/browser_split_view_with_glance.js`

## Frozen user-visible behavior

- `Open Link in Glance` is exposed only for real link targets and is hidden for
  `mailto:` and `tel:` links.
- Glance opens only for `http`, `https`, or `file` URLs.
- Glance may also open from:
  - bookmark activation using the configured modifier
  - search-result tab openings when Zen's search-glance path is enabled
  - external-link opens from pinned essential-like app tabs when Glance is
    enabled and the destination domain differs
- Every live glance is parent-linked:
  - the preview child gets `zen-glance-tab` and `glance-id`
  - the parent keeps the same `glance-id`
- Workspace filtering must always keep a live glance visible.
- When the parent moves to another workspace, the glance child mirrors the same
  workspace id.

## Selection and traversal parity

- Selecting the parent of a live glance re-selects the glance child instead of
  leaving focus on the parent shell row.
- Sequential next or previous tab traversal from a live glance follows the
  parent-adjacent ordering, not the raw child tab placement.
- switching away from a live glance closes only the visible overlay state and
  preserves the live parent-child linkage
- returning to the parent or live child reopens the glance path instead of
  degrading it into an unrelated normal tab
- Aura must preserve the equivalent of Zen's `getTabOrGlanceParent`,
  `getTabOrGlanceChild`, and directional `getFocusedTab` remapping.
- Drag, split targeting, tab traversal, and shell selection must operate on the
  remapped parent or child consistently instead of mixing raw tab ids.

## Sidebar and count parity

- a live glance is not a standalone normal sidebar row
- Zen implements the live glance child as a nested tab inside the parent row:
  - `ZenGlanceManager` appends the child tab into the parent `.tab-content`
  - parent rows expose the child through `tab.glanceTab`
  - in collapsed or essentials-style rows this renders as a trailing child-chip
    affordance instead of a separate sidebar row
- a live glance is excluded from the normal counts used for:
  - visible tab ordering
  - pinned counts
  - essentials counts
- moving the parent tab to another space moves the live glance child with it
- the parent keeps the visible sidebar identity while the glance remains a
  parent-adjacent transient affordance
- if the parent is Essential-backed, the live glance child still stays outside
  the Essentials counting and container rules

## Close and dismiss parity

- Clicking the overlay outside the glance content closes the glance if unload
  is permitted.
- If the page blocks unload, Glance close is blocked.
- If the parent tab closes, the glance closes as well.
- Focused close uses a confirmation affordance:
  - the close button enters `waitconfirmation`
  - the confirmation window lasts `3000ms`
  - the label expands while confirmation is armed
- Closing a glance removes both parent and child `glance-id` linkage.
- Closing a glance must not leave the parent visually selected incorrectly.

## Expand parity

- Expanding Glance removes all glance-only attributes and converts the preview
  into a normal tab.
- The expanded tab moves immediately to the right of the parent tab.
- If the parent is pinned, the expanded tab becomes the first normal visible
  tab after the pinned region.
- If the parent is Essential-backed, the expanded tab is not pinned and does
  not remain inside the Essentials container.
- Reduced-motion mode skips the full expand animation and settles immediately.
- Expand uses the same command owner everywhere:
  - overlay button
  - keyboard command
  - future menu entrypoints

## Split parity

- `Split Glance` is not a generic "insert into any split" path.
- Zen semantics are exact:
  - fully open the glance first with split-specific handling
  - split only the pair `parent + glance`
  - reverse the pair order when the sidebar is on the right
- If split capacity is already full, the split command is disabled.
- Expanding a glance from an existing split removes the glance-only state and
  keeps the original split group intact.
- Splitting a glance makes the former preview tab a normal split-group member
  with the parent.

## Visual parity

- grounded Zen sources expose overlay controls, not a separate glance context
  menu
- Glance overlay controls are a dedicated vertical cluster in this order:
  1. `Close`
  2. `Expand`
  3. `Split`
- The control cluster is:
  - positioned `15px` from the top edge
  - padded `12px`
  - gapped `12px`
  - capped at `56px` width
- On left-side tabs it anchors just outside the right edge of the preview.
- On right-side tabs it anchors just outside the left edge of the preview.
- Overlay controls are round, shadowed, hover-scale buttons using mirrored Zen
  icons.
- The parent background scales to `0.97` while glance is open.
- The preview opens at `80%` width before full-expand animation.

## Aura clean-room translation rules

- Aura must preserve the behavior above without copying Zen's fake-tab or
  placeholder internals.
- Aura must not widen Glance into a more permissive arbitrary split-insertion
  model in v1.
- Aura must keep Glance runtime event-driven:
  - no polling loops
  - no second preview runtime
  - no view-local fallback heuristics for parent or child remapping

## Still explicitly lower-confidence

- the exact internal-page bypass matrix beyond the grounded `http/https/file`
  allowlist
- future multi-window Glance behavior if Aura later adds Zen-style window sync
