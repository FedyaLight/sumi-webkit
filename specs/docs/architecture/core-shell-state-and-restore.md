# Core shell state and restore

Aura restore must rebuild shell state from explicit persisted contracts, not
from view heuristics.

## Persisted state

### `AuraProfileState`

Profile-owned data:

- ordered spaces
- ordered essentials launcher list for the profile
- ordered pinned section tree for each space
- ordered root entry tree for each space
- launcher titles, canonical URLs, and optional custom launcher icons
- pinned extension ordering
- per-space workspace themes

### `AuraCustomizationState`

Customization-owned data:

- Aura keyboard preferences
- Aura workspace navigation preferences
- Aura compact-mode preferences
- internal customization schema versioning metadata

### `AuraWindowState`

Window-owned data:

- window mode
- active space
- collapsed pinned sections by space for the current window
- current selection
- expanded folders
- compact mode state
- live essential attachment records
- media card dismissal state
- MRU tab order
- split layout state
- glance restore hint

## Transient runtime state

Not persisted directly:

- active drag session
- current drop preview
- current hover-open timer
- current address bar query and presentation
- current URL bar learner history
- current pinned-launcher changed-url slash and reset state
- current empty-space surface projection
- current folder placeholder projection
- current profile runtime lifecycle state
- media card hover/expanded affordances
- glance close-confirmation countdown state
- ephemeral menus and popovers

## Restore rules

1. missing folder ids are dropped from `expandedFolderIds`
2. missing ids are dropped from `collapsedPinnedSpaceIds`
3. missing selection targets fall back to the first valid tab in the active
   space
4. split restore is best-effort:
   - persisted `layoutTree` is the sole canonical split structure
   - any cached projected split items are rebuilt from the tree and ignored if
     they disagree
   - if one member is missing, collapse the split and keep the surviving tab
   - if all members are missing, drop the split record
5. glance restore is best-effort:
   - if parent or preview target is missing, drop glance entirely
   - never restore the transient close-confirmation countdown state
6. live essentials restore is best-effort:
   - if the live tab no longer exists, release the live instance and keep the
     launcher
   - if the live essential was showing a split-proxy slot but the split no
     longer exists, restore the normal launcher slot
   - if a split created from an essential was already detached through pinning,
     never relink it to the launcher during restore
7. compact mode restore is best-effort:
   - if the persisted policy is invalid for the current window layout, fall
     back to `hide sidebar`
   - hover-revealed chrome never restores as permanently visible unless that
     visibility was explicitly keyboard-locked
8. media card restore is best-effort:
   - dismissed media state restores only as playback epoch ids
   - if a dismissed epoch no longer exists, the dismissal record is dropped
   - dismissal must not hide a new playback epoch forever

## Transient surfaces

- Ctrl+Tab panel never restores
- unified hub never restores
- theme editor never restores
- sidebar context menus never restore
- media menus never restore

## Address bar restore rules

- the address bar itself is not restored open after restart
- remembered query text does not survive restart
- command-result priority and focus-return behavior are runtime rules, not
  persisted window state
- learner state persists separately from both window restore and customization
  import/export

## Space transition restore rules

- partial or in-flight space-switch UI state (not persisted) never restores after restart; the shell always resumes with a single committed active space
- startup always resumes in a settled committed space
- theme blending restarts from the committed destination state only
- an active empty space may restore with a dormant profile runtime until the
  first runtime-backed action occurs

## Blank window restore rules

- blank windows restore as `blank` windows, not as degraded standard windows
- blank windows do not restore standard shell tree state
- standard windows do not fall back to blank mode when sidebar state is missing
- startup restore must remember the active space only for standard windows

## MRU and focus restoration

- `mruTabIds` is window-scoped
- MRU restoration never crosses spaces
- if the remembered tab belongs to a different profile but the same active
  space, it may be restored
- if the remembered tab is gone, fallback stays inside the active space

## Future multi-window compatibility

- `windowId` remains stable and distinct from `profileId`
- split, glance, MRU, and expanded-folder state remain window-scoped
- `AuraCustomizationState` contains internal global customization state
- `AuraCustomizationBundle` remains the import and export format for Aura-owned
  personalization
- `AuraProfileState` contains per-profile structure
- `AuraWindowState` contains window runtime, view, and focus state
- profile runtime lifecycle remains transient and recomputed from live
  conditions after startup

This keeps future Zen-style window sync possible without merging routing and
shell selection into the same store.
