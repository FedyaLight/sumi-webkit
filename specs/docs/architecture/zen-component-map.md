# Zen component map for Aura

This document maps major Zen UI areas to their repository modules so Aura can
borrow the right behaviors without cargo-culting unrelated implementation
details.

## Purpose

When implementing Aura on top of Helium, we should know two things:

- which Zen module likely owns a behavior
- which Aura layer should own the equivalent behavior on Helium

This keeps us from smearing one Zen feature across many Aura components.

## Zen source map

### Global UI inclusion

Zen's browser chrome is centrally layered through an assets include manifest
that loads styles and scripts for:

- sidebar and tabs
- workspaces or spaces
- split view
- folders
- live folders
- glance
- Ctrl+Tab panel
- compact mode
- browser theme and omnibox

### Feature to Zen module mapping

| Feature | Zen source area | Aura owner on Helium |
|---|---|---|
| Vertical tabs and sidebar shell | `src/zen/tabs/**` | `AuraShellCoordinator` + native sidebar host |
| Spaces and workspace switcher | `src/zen/spaces/**` | `AuraProfileRouter` + sidebar shell |
| Split view | `src/zen/split-view/**` | `TabModelAdapter` + interaction engine |
| Glance | `src/zen/glance/**` | `TabModelAdapter` + interaction engine |
| Folders | `src/zen/folders/**` | `AuraShellCoordinator` + persisted sidebar tree |
| Live folders | `src/zen/live-folders/**` | future Aura service, not part of first frozen core shell |
| URL bar and command actions | browser base Zen UB components | canonical address bar + shell command routing |
| Compact mode | `src/zen/compact-mode/**` | centralized compact-mode controller in shell |
| Ctrl+Tab panel | Zen ctrl-tab panel include and scripts | future Aura panel or native host, not ad hoc tab UI |
| Theme tokens | Zen theme CSS | `AuraThemeService` and native chrome styling |
| Theme picker | `src/browser/base/content/zen-panels/theme-picker.inc` and `src/zen/spaces/ZenGradientGenerator.mjs` | `AuraThemeService` + native theme picker adapter |
| Settings IA | browser preferences / Zen preferences surfaces | `AuraCustomizationService` + `aura://settings/` |

## Aura implementation translation

Zen module ownership should translate into Aura ownership like this:

- sidebar visuals and geometry:
  - native Helium surfaces
  - mounted through `BrowserChromeAdapter`
- interaction policy:
  - `AuraShellCoordinator`
- profile and space semantics:
  - `AuraProfileRouter`
- split and glance runtime verbs:
  - `TabModelAdapter`
- theme application:
  - `AuraThemeService`
- media:
  - Helium runtime as source of truth
  - `AuraMediaSessionService` as translation layer only

## Anti-patterns this map helps avoid

- do not implement split rules inside sidebar view code
- do not implement profile routing inside tab visuals
- do not let compact mode become a local concern of the toolbar only
- do not let URL bar command routing leak into random menus
- do not let theme-editor preview become a second theme owner
- do not copy Zen file boundaries blindly when Helium already owns the runtime

## Scope note

This map is not a porting checklist for every Zen file. It exists to point Aura
engineers at the right behavioral source and the right downstream owner.
