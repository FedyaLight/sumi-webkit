# Zen theme runtime gap audit

This document records the remaining gaps between Aura's frozen theme model and
the live Zen runtime.

## Grounded Zen runtime facts

Grounded against:

- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/base/content/zen-panels/theme-picker.inc`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/ZenGradientGenerator.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/zen-gradient-generator.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/common/styles/zen-theme.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/common/modules/ZenMenubar.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/urlbar/ZenUBGlobalActions.sys.mjs`

Zen runtime currently behaves like this:

- active workspace changes route through `gZenThemePicker.onWorkspaceChange`
- live editing routes through `updateCurrentWorkspace(true)`
- closing the picker commits via `handlePanelClose -> updateCurrentWorkspace(false)`
- scheme buttons do not save into workspace theme state; they set the global
  pref `zen.view.window.scheme`
- dark-mode bias and acrylic-elements are global prefs that affect theme
  rendering and shell surfaces
- the same owner updates browser background, toolbar background, primary color,
  toolbox text color, picker controls, and live picker harmony state

## Where Aura now matches Zen closely

- per-space theme owns gradient colors, opacity, texture, algorithm, and
  monochrome choice
- global shell state now owns window scheme mode, dark theme style,
  dark-mode bias, and acrylic-elements
- picker geometry, page buttons, opacity range, and texture-step count are
  frozen against live Zen values
- picker overlay placement, swatch sizes, hover/press scale, primary dot
  hierarchy, texture-ring dimensions, and macOS native-vs-nonnative material
  split are now frozen against live Zen values
- all picker entrypoints route to one owner instead of separate code paths
- preview and saved commit are frozen to use the same runtime path

## Remaining non-1:1 areas

### Gradient generation math

Aura now freezes Zen's current render branches in:

- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-theme-render-parity.md`

The remaining risk is no longer "unknown branch behavior", but only native
implementation fidelity.

### Internal harmony behavior

Aura freezes `singleAnalogous` as a real editor/runtime detail, but it is still
not a first-class saved algorithm.

This matches Zen's spirit better than pretending it does not exist, but it is
still not a byte-for-byte state match.

### Visual control fidelity

The remaining risk is now mostly live native fidelity, not missing source
grounding:

- exact opacity-wave morphing once rendered in Helium-native controls
- exact texture-ring handler motion and active-dot sweep once mounted in native
  surfaces
- exact invalid-control hide path when Zen treats the theme as default or
  legacy

### Saved representation

Aura may keep a downstream saved preset reference per workspace theme. Zen's
runtime theme object itself is much thinner:

- `type`
- `gradientColors`
- `opacity`
- `texture`

This is acceptable if user-visible behavior stays aligned, but it is not a
literal internal clone of Zen.

## Risks if we do nothing

- pretending scheme mode is per-space would make theme switching feel subtly
  wrong compared with Zen
- abstracting gradient generation too aggressively could make the picker feel
  right while the live chrome looks different
- splitting preview and commit into separate owners would recreate the
  Aura-webkit class of theme/runtime drift

## Required follow-up before calling theme parity complete

- implement the grounded render branches and picker geometry in the live native
  theme owner
- preserve toolbar-background vs browser-background divergence during native
  wiring
- keep scheme mode global in service boundaries and settings UI
- verify that live native picker wiring preserves Zen's preview-then-commit
  semantics without a second runtime path
- tune native material feel only after the Helium-backed picker is runnable,
  because that last step depends on real compositor output rather than source
  tokens alone
