# Ctrl+Tab panel and transient surfaces

Aura treats the Ctrl+Tab panel as a distinct transient shell surface rather
than a special case hidden inside tab traversal code.

## Why this matters

Zen exposes a dedicated Ctrl+Tab panel with explicit markup and manual focus
behavior. Reproducing that cleanly on Helium means we should model it as a
surface with a clear owner and lifecycle.

## Ctrl+Tab panel rules

- the Ctrl+Tab panel is transient and never restored after restart
- it is keyboard-first and may exist without pointer hover affordances
- it must use explicit focus management rather than relying on default
  autofocus behavior
- it must follow the same MRU or sequential traversal source of truth already
  owned by Aura shell state
- it must not become a second tab-selection model

## Ownership

- `AuraShellCoordinator` owns visibility and selection semantics
- `BrowserChromeAdapter` owns the mount point and focus handoff to native
  surfaces
- `TabModelAdapter` continues to own real tab activation only

## Surface behavior

- opening Ctrl+Tab panel samples current tab ordering from the current shell
  traversal mode
- cycling inside the panel changes preview selection only until commit
- dismissing the panel without commit restores focus to the previously focused
  surface
- committing selection activates the chosen tab through the same tab activation
  path as every other shell action

## Transient surface policy

The Ctrl+Tab panel belongs to the broader class of transient surfaces:

- Ctrl+Tab panel
- unified hub
- media menus
- sidebar context menus
- ephemeral popovers

Rules:

- transient surfaces do not restore after restart
- transient surfaces do not own durable app state
- transient surfaces may hold runtime selection state, but they commit through
  canonical service owners

## Performance rule

The Ctrl+Tab panel may not introduce its own polling or duplicated traversal
graph. It is a projection of existing shell state, not a second runtime.
