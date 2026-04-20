# Implementation roadmap

## Immediate next code steps

1. Finish the core shell spec freeze and keep it as the single implementation
   source of truth.
2. Keep Zen source grounding and component map beside the shell spec so native
   rewrite work stays tied to real upstream evidence.
3. Add the first Aura-owned native sidebar host in `BrowserView` and
   `VerticalTabStripRegionView`.
4. Add the first Aura address-bar customization path in `ToolbarView` and
   `LocationBarView`.
5. Introduce `AuraCustomizationState`, `AuraCustomizationBundle`,
   `AuraProfileState`, and `AuraWindowState` loaders and savers with clean
   internal-vs-import/export separation.
6. Add adapters for current tabs, profiles, and media sessions.
7. Add `aura://settings/` customization surface and handlers with the frozen
   `Theme`, `Layout`, `Spaces & Essentials`, `Keyboard`, and `Import/Export`
   IA.
8. Add the native theme picker anchor path and implement the grounded Zen theme
   render recipe branches inside `AuraThemeService`.
9. Add the Helium-backed media card host.
10. Bind Aura models to real Helium runtime-backed data and remove remaining
   placeholder surfaces.

## Scope boundaries already frozen

- blank windows are first-class window mode, not a fake space
- Ctrl+Tab is a transient surface, not a second tab-selection runtime
- live folders remain outside the first shell rewrite until they get their own
  service owner
- sidebar density and panel/menu surface rules are frozen for the single-toolbar
  shell before the first native rewrite

## Definition of done for the first runnable Aura shell

- opens inside Helium macOS build
- renders Aura sidebar and address bar inside the real Helium native view tree
- receives spaces, media sessions, and pinned extension state from Helium-owned
  runtime services
- routes actions back into the same Helium runtime without a parallel shell
- does not introduce a second URL bar or media owner
