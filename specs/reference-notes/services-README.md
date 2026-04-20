# Aura services

Service layer ownership is fixed:

- `AuraShellCoordinator`
- `AuraUrlbarActionService`
- `AuraProfileRouter`
- `AuraCustomizationService`
- `AuraThemeService`
- `AuraMediaSessionService`
- `AuraSiteControlsService`

Services are the only source of product truth for Aura behaviors.

In particular:

- `AuraShellCoordinator` owns the interaction engine and restore order
- `AuraUrlbarActionService` owns URL bar actions, prefixed command semantics,
  and learner state
- `AuraProfileRouter` owns profile routing and live essential attachment
- `AuraCustomizationService` owns import/export/reset and static
  personalization state such as global Essentials definitions, saved theme
  colors, and Aura-owned appearance preferences
- `AuraThemeService`, `AuraMediaSessionService`, and
  `AuraSiteControlsService` feed shell state but do not own drag, split, or
  glance policy

All C++ product code in this repo uses `namespace aura_browser`, not
`namespace aura`, to avoid collisions with Chromium's existing `aura`
windowing namespace.
