# Empty Space And Folder Runtime

Aura preserves Zen user-visible behavior for empty spaces and active folders,
but does not copy Zen's `zen-empty-tab` or `owned-tabs-in-folder` internals.

## Empty space model

- Aura uses `AuraEmptySpaceSurfaceState` for the empty-space fallback
- the empty-space surface is a runtime projection, not a synthetic tab
- switching to an empty space selects its blank or new-tab affordance
- removing that space exits the empty-space surface cleanly
- tab traversal, split targeting, glance promotion, and restore exclude the
  empty-space surface unless explicitly intended

## Folder runtime model

- Aura uses `AuraFolderRuntimeState` for collapsed or projected folder state
- Aura uses `AuraFolderProjectionState` for active-child projection and reset
  affordances
- Aura persists optional `folderIconAsset` on folder entries
- Aura uses `AuraFolderIconPresentationState` for icon open/active projection
- Aura uses `AuraFolderPlaceholderState` only as a view/runtime projection when
  a placeholder is visually needed
- placeholders never participate in runtime tab ids, selection ids, split ids,
  or restore ids

## Frozen Zen-parity behaviors

- a selected child inside a collapsed folder remains visible as an active
  projection
- a previously active child may remain projected after selection leaves
- folder reset clears the active projection state
- nested subfolder depth stops at `5`
- folder row density must match tab row density
- the folder icon lives inside the folder shell itself, not as a separate
  trailing badge
- custom folder icons persist and fall back cleanly to the default folder glyph
- split groups created from folder tabs keep the folder parent linkage
- pinning or unpinning one split member propagates to the whole split group

## What Aura intentionally does not copy

- no synthetic `zen-empty-tab` implementation
- no empty placeholder tab becoming the first real runtime tab
- no `owned-tabs-in-folder` coupling as a required internal primitive

Aura may later add optional child-tab inheritance for folder-hosted tabs, but
only as an Aura-owned runtime policy hook, not as a hidden structural rule.
