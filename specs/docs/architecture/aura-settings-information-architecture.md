# Aura settings information architecture

`aura://settings/` is the canonical home for Aura-owned settings that do not
belong in the always-live native browser chrome.

## Top-level sections

The first decision-complete Aura settings IA contains exactly:

1. `Theme`
2. `Layout`
3. `Spaces & Essentials`
4. `Keyboard`
5. `Import/Export`

## Theme

Contains:

- per-space theme editor entry
- global window scheme mode
- global dark theme style
- global dark-mode bias
- acrylic-elements toggle
- the same scheme, preset-page, harmony, opacity, and texture concepts the live
  theme picker exposes

Does not contain:

- website light/dark overrides
- content rendering theme controls
- a second standalone theme runtime that bypasses the live picker owner
- a saved custom-color library separate from the live Zen-style picker

## Layout

Contains Aura-owned shell layout and visibility preferences:

- layout mode, defaulting to `Single Toolbar`
- `Tabs on Right`
- compact mode preferences
- compact themed background
- URL bar behavior mode
- URL bar copy-link visibility
- URL bar PiP visibility
- URL bar contextual identity visibility

Multi-toolbar and collapsed-toolbar variants remain explicitly deferred even if
their future ids exist in the model.

## Spaces & Essentials

Contains:

- Essentials definitions per profile
- space ordering and space-level metadata summaries
- space/profile semantics help text

It must not directly edit live runtime attachments for active Essential
instances.

## Keyboard

Contains:

- Aura-owned traversal preferences
- Aura workspace wrap-around preference
- `open new tab if last unpinned tab closes`
- Aura-owned shortcut settings once live UI exists

Advanced shortcut rebinding UI remains deferred, but the section still exists as
its future canonical home.

## Import/Export

Contains:

- export customization
- import customization
- replace-current confirmation
- reset customization
- bundle compatibility and warning messaging

The bundle scope remains `shell settings only`.

Adaptive URL bar learner history is intentionally not part of import/export and
remains a local store.

## Explicit non-goals for settings IA

`aura://settings/` must not duplicate these live chrome surfaces:

- site controls / unified extensions popover
- media cards
- context menus
- transient theme picker geometry

Settings own preferences and import/export, not the always-live browser-panel
runtime.

## Ownership rules

- `AuraCustomizationService` owns import, export, replace, and reset
- `AuraThemeService` owns theme save and preview
- `AuraProfileRouter` owns live profile routing semantics
- the settings page reads a typed customization snapshot from canonical
  services; it never rebuilds settings state by parsing its own export JSON
- the settings page calls services only and never writes JSON directly
