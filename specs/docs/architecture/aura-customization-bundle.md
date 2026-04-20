# Aura customization bundle

This document freezes the versioned import and export contract used by
`aura://settings/`.

## Purpose

The customization bundle exists to move Aura-owned personalization between
installs without conflating it with browsing session restore.

It is not a profile clone, not a tab/session snapshot, and not a browser-data
backup.

## Bundle contents

Included in v1:

- Essentials definitions per profile
- saved custom theme colors
- Aura keyboard preferences
- Aura workspace navigation preferences
- Aura compact-mode preferences
- Aura layout preferences
- Aura URL bar behavior preferences
- Aura URL bar copy-link, PiP, and contextual-identity visibility preferences
- Aura acrylic-elements toggle
- Aura global window scheme mode
- Aura dark theme style preference
- Aura dark-mode bias value
- spaces per profile
- folders and launcher trees per profile, including launcher titles, canonical
  URLs, and custom emoji or SVG icon overrides
- pinned section entries per profile
- pinned extension ordering per profile
- per-space workspace themes

Excluded from v1:

- open tabs
- browsing history
- cookies or site data
- extensions data
- current active window selection
- split and glance runtime state
- media card runtime state
- transient surfaces
- live Essential instances
- URL bar learner history

## Import mode

- import mode is `Replace current`
- the user must see a preview and explicit confirmation before apply
- partial merge behavior is intentionally out of scope for v1

## Validation and migration

- the bundle is human-readable JSON
- the bundle is schema-versioned
- the bundle must validate before apply
- invalid or incompatible bundles fail cleanly with no partial mutation
- forward migration is allowed through canonical Aura migration logic

## Ownership

- `AuraCustomizationService` owns bundle construction, preview, validation,
  replace, and reset
- settings UI triggers those service methods and must not write bundle JSON
  directly
- internal `AuraCustomizationState`, `AuraProfileState`, and `AuraWindowState`
  remain separate persistence concerns

## Relation to persisted state

- `AuraCustomizationState` remains the internal persisted global-customization
  store
- `AuraProfileState` remains the internal per-profile structure store
- `AuraWindowState` remains the internal window runtime/view store
- `AuraUrlbarLearnerState` remains a separate local adaptive store
- `AuraCustomizationBundle` is the import/export format for Aura-owned
  personalization only
