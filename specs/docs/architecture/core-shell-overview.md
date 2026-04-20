# Core shell overview

This document freezes the first complete Aura shell model before any larger
native rewrite pass continues.

## Goal

Aura must feel like Zen in core interaction behavior while staying a rewritten
native Helium interface instead of a parallel shell runtime.

## Window model

- single-window-first
- each space is bound to one Chromium profile
- switching spaces swaps the active browsing context in-place
- data contracts must stay compatible with future multi-window sync, but v1
  behavior is authored for one primary Aura window

## Visible shell hierarchy

1. window frame and browser host
2. Aura sidebar shell
3. top chrome and canonical address bar
4. active space entry tree
5. `New Tab` affordance
6. background media card stack
7. content host
8. overlay surfaces:
   - site-controls hub
   - theme editor
   - glance surface
   - split controls
   - context menus

## Sidebar composition

- top area: navigation controls plus canonical address bar
- essentials area: profile-owned launchers; spaces that share a profile reuse
  one shared strip
- profile/space area: active space switcher and per-space pinned section
- entry tree area: regular launchers and nested folders for the active space
  only
- footer area: `New Tab` button and media cards

Split-backed content keeps Zen's grouped sidebar presentation:

- a split renders as one grouped sidebar unit, not as flattened unrelated rows
- that grouped unit may appear in the pinned section, in the regular tree, or
  as a child of a folder
- a live glance remains a parent-adjacent transient affordance and not a normal
  standalone sidebar entry

The space switcher should collapse out of view when there is only one space,
matching Zen’s bias toward reducing chrome when switching affordances are not
needed.

The active space header row also acts as the collapse toggle for that space's
pinned section, matching Zen's pinned-tab folding behavior.

## Source of truth

- Helium/Chromium owns:
  - real tabs and web contents
  - profiles
  - navigation
  - split-capable content hosting
  - glance-capable preview hosting
  - media session detection and control
- Aura owns:
  - sidebar tree structure
  - spaces and profile routing
  - essentials semantics
  - per-space pinned launcher and pinned-tab presentation
  - workspace chrome theme
  - customization import and export through `aura://settings/`
  - native chrome composition
  - interaction policy for drag, reorder, split, glance, restore

## Hard invariants

- one interaction engine for the whole shell
- one URL bar implementation
- one media registry
- one theme owner
- no per-component drag logic
- no hidden fix-up pass after a drop or split operation
- no view-position-driven mutations; all shell mutations are id-based
- no second runtime for media or tab state

## Restore order

1. load `AuraCustomizationState`
2. load all required `AuraProfileState` records for the window
3. load `AuraWindowState`
4. bind active space to its profile
5. rebuild essentials and sidebar tree
6. restore selected tab or launcher
7. restore split state
8. restore glance if parent linkage is still valid
9. apply workspace theme
10. attach media shell state

## Aura-specific divergence from Zen

- essentials are owned by the active profile, not by the window
- switching between same-profile spaces keeps one shared Essentials strip fixed
- live swipe between different profiles falls back to page-owned Essentials so
  the strip moves with the swiped page
- a live essential remains attached to the profile where it was opened
- once that live instance is closed or unloaded, relaunch uses the current
  space profile
