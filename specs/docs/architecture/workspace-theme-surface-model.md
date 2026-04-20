# Workspace theme surface model

Global light/dark and workspace theme are separate.

## Ownership

- `AuraThemeService`
- one `WorkspaceThemeCoordinator`

## Rules

- workspace theme colors Aura chrome only
- site rendering follows global light/dark, not workspace color
- editor preview and runtime application use the same coordinator
- space switching blends theme during the transition, not after it
- per-space theme state supports monochrome mode and explicit color algorithm
  choice
- theme editing supports multiple color points, capped at `3`
- theme editing exposes global window scheme controls: `auto`, `light`, `dark`
- window scheme mode is global shell state, not part of per-space saved theme
- theme editing infers Zen's internal `singleAnalogous` state for two-point
  layouts but persists only public algorithms
- theme editing uses the Zen picker geometry for the first parity pass:
  - `380px` bounded panel width
  - `10px` panel padding
  - near-square gradient field with min-height
    `calc(panel-width - panel-padding * 2 - 2px)`
  - `30px` scheme and action buttons
  - `28px` page navigation buttons
  - `5px` overlay-button gaps
  - `15px` scheme-row top inset
  - `26px` preset swatches with hover/press scaling
  - `38px` primary draggable color point with `6px` white border
  - action row anchored inside the field
  - panel opening to the right of the left sidebar when space allows
- theme editing may keep a saved preset reference with the per-space theme, but
  current pager position remains transient
- theme editing exposes opacity and texture controls
- theme editing ends after presets, opacity, and texture; there is no saved
  custom-color section
- opacity is constrained to the Zen-grounded macOS range of `0.30..0.90`
- texture strength is quantized to Zen's current `16` ring steps
- texture control follows the current Zen ring language:
  - `5rem` wrapper size by default
  - `6rem` on macOS
  - `4px` ring dots
  - vertical handler that moves around the ring
- picker uses the mirrored Zen icon family:
  - `sparkles`
  - `face-sun`
  - `moon-stars`
  - `plus`
  - `unpin`
  - `algorithm`
  - `arrow-left`
  - `arrow-right`
- all theme picker entrypoints route to the same `AuraThemeService` owner:
  spaces menu, menubar appearance, URL bar actions, and workspace creation flow
- invalid theme input must degrade cleanly instead of corrupting chrome state
- live preview and saved commit must share the same runtime path
- scheme changes must apply immediately through the global theme owner instead
  of waiting for a per-space save
- runtime rendering must follow the grounded Zen branch model:
  - `0` colors: default browser/toolbar fallback
  - `1` color: single-color path
  - `2` colors: dual layered browser field plus single toolbar gradient
  - `3` colors: one linear layer plus two radial layers
- browser and toolbar backgrounds must be allowed to diverge exactly where Zen
  diverges
- on macOS the picker must honor Zen's native-vs-nonnative popover split:
  - native arrow popovers use transparent background and OS shadow
  - no-tail bounded pickers are allowed
  - non-native fallback uses menu-like background intentionally
- dark theme style remains a global Aura-owned setting with `default`, `night`,
  and `colorful` options
- dark-mode bias and acrylic-elements remain global Aura-owned shell settings
- picker visibility, page position, and temporary `nonnativepopover` forcing
  remain transient and never persist
