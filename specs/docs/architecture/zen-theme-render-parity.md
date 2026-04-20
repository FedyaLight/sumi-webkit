# Zen theme render parity

This document freezes the exact Zen theme-render branches Aura should copy for
the first native implementation.

## Grounding

Grounded directly from:

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/ZenGradientGenerator.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/spaces/zen-gradient-generator.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/common/styles/zen-theme.css`

## One owner

Aura must treat theme rendering as one runtime owner:

- preview while editing
- commit on picker close
- live space-switch interpolation
- browser background
- toolbar background
- primary color
- toolbox text contrast
- grain or texture state

No second theme path is allowed.

## Global vs per-space state

Zen currently splits theme state like this:

- global:
  - window scheme mode via `zen.view.window.scheme`
  - `zen.theme.dark-mode-bias`
  - `zen.theme.acrylic-elements`
- per workspace:
  - `gradientColors`
  - `opacity`
  - `texture`

Aura should mirror this separation.

## Chrome surfaces vs workspace gradient (Sumi)

Native chrome (sidebar toolbox, URL field, panels) is **not** workspace-gradient tinted; the floating **command palette** uses a flat light/dark surface. No user-defined accent drives these fills. Sumi follows Zen’s model:

- **Neutral chrome base** (`neutralChromeBackground`): light chrome uses **pure white**; dark uses fixed neutrals per `darkThemeStyle`. Used for opaque strips, toasts, and panel lifts — **not** under the URL field or Essentials tiles.
- **Panel lift** (`panelBackground`): neutral **elevated** surface from `elevatedNeutral` (e.g. toolbar strip, toasts, **in-flow** sidebar panels such as the sidebar menu column). Prefer **not** for floating popovers when you want the flat Zen “sheet” look.
- **Essentials / pinned tiles**: idle/hover use the URL-bar **veil** (`fieldBackground` / `fieldBackgroundHover`); **selected** (live tab is this essential) uses `sidebarRowActive`, same as a selected tab row (e.g. white lift in light chrome). Hub header / extension hub tile gradients use `ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors` so stops stay in one place.
- **URL hub / identity / zoom popovers**: solid `commandPaletteBackground` (white / near-black) so they track chrome scheme, not the neutral panel lift.
- **Peek overlay** card surfaces and **folder icon picker** sheet: same **solid** `commandPaletteBackground` as the command palette (floating card, not sidebar lift).
- **Theme picker** (`GradientEditorView`): **opaque** `commandPaletteBackground` for the panel; handle halos on the canvas use the same token so edges stay clean on the solid card.
- **Toolbar elements** (URL bar, inputs): **Zen `--zen-toolbar-element-bg` parity** — **only** translucent ink (`Color.black` / `Color.white` at low alpha) composited over whatever is behind the control (window gradient in the sidebar). Hover adds another `rgba`-style overlay via `zenToolbarElementHoverBackground`.
- **Command palette** (floating): **solid** `commandPaletteBackground` — white in light chrome, near-black (`#1C1C1E`) in dark — separate from `panelBackground`. In-list selection/hover use `commandPaletteRowSelected` / `commandPaletteRowHover`; chips use `commandPaletteChipBackground`. **Local vignette:** multi-layer soft shadows only around the card (`CommandPaletteLocalVignetteModifier` in `CommandPaletteView`) so the palette separates from bright page content **without** a full-window dim (unlike a page-wide scrim). Reduce Transparency: lighter shadow + stronger stroke.
- **Elevated panels** (toolbar strip, toasts): neutral **white/black lift** from the chrome base (`elevatedNeutral`), not accent mixing.
- **Primary / accent for controls**: system `NSColor.controlAccentColor` only (Zen default `AccentColor`), for buttons, carets, and similar — not for painting the URL bar fill.

**Workspace gradient** remains the sole owner of colorful backdrop behind chrome; `ThemeContrastResolver` picks light vs dark chrome text using the workspace gradient primary when “Use System Colors” is off.

## Exact render branches

### 0 colors: default theme

Browser background:

- if transparency is allowed:
  - dark: `rgba(0, 0, 0, 0.4)`
  - light: `transparent`
- otherwise:
  - dark: `#131313`
  - light: `#e9e9e9`

Toolbar background:

- always uses `getToolbarModifiedBase()`

### 1 color: single-color path

- use Zen's single-color transform path
- apply toolbar/base blending rules before final overlay if needed
- result is a single solid RGBA color for browser or toolbar surface

### Custom colors present: custom linear path

- use one evenly distributed `linear-gradient`
- fixed rotation: `-45deg`
- distribute color stops evenly from `0%` to `100%`
- this path replaces the normal `2`-color or `3`-color structural branches

### 2 colors: dual layered path

Browser background:

- two opposing linear layers
- first:
  - `linear-gradient(-45deg, color2 0%, transparent 100%)`
- second:
  - `linear-gradient(135deg, color1 0%, transparent 100%)`
- final order matches Zen's current `.reverse().join(", ")` result

Toolbar background:

- one opaque `linear-gradient(-45deg, color2 0%, color1 100%)`

### 3 colors: triple layered path

Use exactly these layers:

1. `linear-gradient(-5deg, color3 10%, transparent 80%)`
2. `radial-gradient(circle at 95% 0%, color2 0%, transparent 75%)`
3. `radial-gradient(circle at 0% 0%, color1 10%, transparent 70%)`

With Zen's current source ordering:

- `color1 = themedColors[2]`
- `color2 = themedColors[0]`
- `color3 = themedColors[1]`

## Base blending and transparency rules

Toolbar modified base raw:

- dark:
  - `[23, 23, 26, 0.6]` if acrylic/transparency is allowed on sidebar
  - `[23, 23, 26, 1]` otherwise
- light:
  - `[240, 240, 244, 0.6]` if acrylic/transparency is allowed on sidebar
  - `[240, 240, 244, 1]` otherwise

When single-color rendering targets:

- toolbar with acrylic disabled
- or browser surface with transparency not allowed

Zen first blends the accent color against the toolbar-modified base before final
surface output.

## Overlay behavior

After color selection, Zen applies one more overlay stage:

- on macOS:
  - white overlay with opacity `0.35`
- on Mica:
  - black or white overlay with opacity `0.25` depending on dark mode

Aura should preserve the same semantic step even if the native implementation
uses platform-native materials instead of CSS strings.

## Rotation and branch selection

- base gradient rotation is currently fixed to `-45deg`
- this is true even though Zen leaves a TODO about future rotation detection
- Aura should copy the current fixed value for parity

## Dark text/light text decision

Zen computes toolbar color scheme from contrast:

- if `zen.theme.use-system-colors` is on, follow global dark mode directly
- otherwise compare contrast against dark and light text candidates
- when transparency is allowed, reduce light-text alpha by `dark-mode-bias`
- choose the better contrast path

Aura should keep this same decision flow instead of replacing it with a simpler
threshold heuristic.

## Grain or texture

- texture updates both browser and toolbar surfaces
- grain visibility is driven by whether texture is greater than zero
- grain opacity equals texture strength

## Preview and commit semantics

- live editor interactions call the same recipe path as runtime changes
- picker close commits the same state if there were edits
- space switching must use the same recipe owner, not rebuild theme from a
  second code path
