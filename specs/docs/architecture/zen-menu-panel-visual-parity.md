# Zen menu and panel visual parity

This document captures the concrete menu and panel values Aura can safely lift
from the local Zen source before the native Helium rewrite is wired.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/common/styles/zen-popup.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/toolkit/themes/shared/popup-css.patch`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/external-patches/firefox/native_macos_popovers.patch`

## Frozen tokens

- arrow panel width used by the theme picker: `380px`
- arrow panel padding: `10px`
- panel subview body padding: `2px 0`
- menu item border radius: `5px`
- menu item padding block: `8px`
- menu item padding inline: `14px`
- menu item margin inline: `4px`
- menu item margin block: `2px`
- menu icon inset: `14px`
- panel separator margin vertical: `2px`
- panel separator margin horizontal: `1px`
- popup shadow margin: `8px`
- native macOS arrow-panel shadow margin: `0px`
- macOS arrow panel radius: `10px`
- macOS Tahoe arrow panel radius: `12px`
- footer button padding block: `20px`
- footer button padding inline: `15px`
- permission-section padding block: `8px`
- permission-section padding inline: `16px`
- permission-row padding block: `4px`
- theme-picker page buttons: `28px`
- theme-picker action and scheme buttons: `30px`
- theme-picker overlay button gap: `5px`
- theme-picker scheme top inset: `15px`
- theme-picker swatch diameter: `26px`
- theme-picker swatch hover scale: `1.05`
- theme-picker swatch active scale: `0.95`
- theme-picker primary draggable dot diameter: `38px`
- theme-picker primary draggable dot border width: `6px`
- site-controls add-on overflow threshold: `420px`
- site-controls add-on tile radius:
  - macOS: `6px`
  - non-macOS: `4px`
- site-controls permission icon frame: `34px`
- site-controls header icon width: `18px`

## Frozen rules

- app menu and large panels must respect available screen height
- native macOS arrow popovers and non-native popovers are distinct cases
- bounded no-tail panels are valid and required for Aura's theme picker
- native macOS arrow popovers use transparent background, transparent border,
  and OS-provided shadow instead of an extra CSS shadow stack
- non-native macOS popovers force a menupopup-like appearance and `Menu`
  background instead of pretending to be native NSPopover
- on macOS, native panels rely on OS shadows while non-native popovers force a
  menupopup-like appearance
- Zen explicitly uses `hidepopovertail` and `nonnativepopover` flags for this
  distinction
- Zen keeps CSS `box-shadow` off the base panel shell and lets the platform or
  specialized surface own the shadow/material language
- one menu system is still required, but it must preserve separate token
  families for context menus and arrow panels
- panel geometry must not depend on sidebar reflow hacks or delayed fix-ups
- the site-controls panel keeps fixed internal section order:
  header, add-ons, settings, footer, messages
- the site-controls section-hover secondary labels are intentional and should
  not be replaced with always-visible buttons in the first parity pass
- theme-picker controls live inside the gradient field itself:
  - scheme row centered at the top
  - action row centered near the bottom
  - both use `30px` icon-only buttons with `5px` gaps
- preset swatches are circular `26px` chips with subtle `1px` ring shadow and
  scale on hover or press instead of changing layout

## Required Aura translation

- `context menu` keeps the frozen `8px` family from Aura's existing shell docs
- `arrow panel/popover` uses the Zen-grounded padding and radius family above
- `persistent transient surface` stays a separate overlay class and must not
  inherit app-menu row geometry by accident
- site-controls popover copies the Zen header-button language instead of
  inventing a second custom site-controls panel style
