# Zen theme picker parity

This document freezes the parts of Zen's theme picker that Aura can mirror
before the first runnable Helium-backed native shell exists.

## Source grounding

Aura is grounded against:

- `/Users/fedaefimov/Downloads/Aura/Aura-webkit/references/Zen/src/browser/base/content/zen-panels/theme-picker.inc`
- `/Users/fedaefimov/Downloads/Aura/Aura-webkit/references/Zen/src/zen/spaces/ZenGradientGenerator.mjs`
- `/Users/fedaefimov/Downloads/Aura/Aura-webkit/references/Zen/src/zen/spaces/zen-gradient-generator.css`
- `/Users/fedaefimov/Downloads/Aura/Aura-webkit/references/Zen/src/browser/themes/shared/zen-icons/icons.css`

## Frozen controls

Aura's first native theme editor must expose:

- global `window scheme mode`: `auto`, `light`, `dark`
- `algorithm`: `complementary`, `splitComplementary`, `analogous`, `triadic`,
  `floating`
- `add color point`
- `remove color point`
- `algorithm toggle`
- preset palette pages
- opacity slider
- texture control

Aura's mirrored picker stops after presets, opacity, and texture, matching the
current Zen panel and intentionally omitting Aura's older saved custom-color
surface.

The editor must cap visible editable color points at `3`, matching Zen's
`MAX_DOTS`.

When the editor has `0` points:

- the action row is disabled
- the canvas shows `Click to add`
- clicking the field creates the primary point

When the editor has `1` point:

- `plus` is enabled
- `minus` remains enabled and clears the field completely
- `algorithm` stays disabled

Zen keeps one additional internal harmony, `singleAnalogous`, as a transitional
toggle state. Aura does not persist it as a first-class saved algorithm for the
first native pass; it remains an editor-internal transition detail unless live
native parity proves it needs durable storage.

## Frozen preset model

Aura stores the chosen preset as a downstream reference, not as guessed Zen
internal ids.

The first native pass uses these page ids:

- `lightFloating`
- `lightAnalogous`
- `darkFloating`
- `darkAnalogous`
- `blackWhite`
- `custom`

`blackWhite` is the explicit black/white preset page Zen ships separately.

Each saved per-space theme may remember:

- selected preset page
- preset id within the page
- whether the explicit black/white page was used
- preset lightness

The live editor's current page position is still transient. Aura may persist a
saved preset reference as downstream metadata, but it must not treat the open
panel's current pager index as durable state.

## Frozen visual rules

- picker width: `380px`
- picker padding: `10px`
- editable gradient field uses Zen's current near-square min-height rule:
  `calc(panel-width - panel-padding * 2 - 2px)`
- opacity slider range on macOS: `0.30` to `0.90`
- texture control snaps to `16` positions around a circular ring
- picker opens as a bounded no-tail arrow panel
- picker anchors from the sidebar trailing edge and clamps inside the window
- the dotted gradient field and opacity wave are part of the editor surface,
  not a separate modal
- scheme row is centered near the top of the gradient field with a `15px`
  inset
- action row is centered near the bottom of the gradient field
- scheme and action buttons are icon-only `30px` controls with `5px` gaps
- page buttons are `28px`
- preset swatches are circular `26px` chips with subtle ring shadow and
  `1.05 / 0.95` hover/press scale
- color points use Zen's current visual hierarchy:
  - regular point diameter `16px`
  - primary draggable point diameter `38px`
  - primary point white border width `6px`
- texture ring uses:
  - wrapper `5rem`
  - wrapper `6rem` on macOS
  - `4px` dots
  - vertical pill handler that moves around the ring
- on macOS, native picker popovers keep transparent background and OS shadow,
  while forced non-native fallbacks intentionally use menu-like background
- picker grain uses Zen's tiled `grain-bg.png`, not a stretched fill texture

## Persistence rules

Persist:

- saved per-space theme state
- global window scheme mode
- global dark theme style

Do not persist:

- picker visibility
- current editor page index
- transient preview values not explicitly saved

## Aura-owned shell prefs required for parity

Even in the first single-toolbar pass, Aura settings must carry the Zen-like
theme-adjacent preferences that affect shell appearance:

- compact themed background
- URL bar behavior mode
- URL bar copy-link button visibility
- URL bar PiP button visibility
- URL bar contextual identity visibility
- acrylic-elements toggle
- dark theme style: `default`, `night`, `colorful`
- dark-mode bias in the range `0.0` to `1.0`

## Known non-1:1 areas

- Zen's scheme buttons are global window controls, not part of saved per-space
  theme state
- Zen's internal `singleAnalogous` harmony remains real runtime behavior, so
  Aura must treat it as an editor/runtime transition detail even if it is not a
  first-class saved algorithm
- Aura still hosts the picker inside its own bounded in-window overlay rather
  than Zen's XUL panel machinery, but the editor math, icons, action states,
  wave interpolation, and texture quantization follow the live Zen runtime
