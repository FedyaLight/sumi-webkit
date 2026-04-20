# Helium UI Entrypoints for Aura

This note records the concrete Helium/Chromium desktop UI files that Aura
should build on top of instead of inventing parallel shell surfaces.

## Primary browser frame

- `chrome/browser/ui/views/frame/browser_view.h`
- `chrome/browser/ui/views/frame/browser_view.cc`

`BrowserView` is the main desktop browser host. This is the top-level entry
point for integrating Aura shell ownership into the real window.

## Vertical tab/sidebar region

- `chrome/browser/ui/views/frame/vertical_tab_strip_region_view.h`
- `chrome/browser/ui/views/frame/vertical_tab_strip_region_view.cc`
- `chrome/browser/ui/views/tabs/vertical/*`

Helium already carries Chromium's vertical tab strip implementation. Aura
should treat this region as the base host for the left shell instead of
building a second sidebar runtime.

## Toolbar and address bar

- `chrome/browser/ui/views/toolbar/toolbar_view.h`
- `chrome/browser/ui/views/toolbar/toolbar_view.cc`
- `chrome/browser/ui/views/location_bar/location_bar_view.h`
- `chrome/browser/ui/views/location_bar/location_bar_view.cc`

These are the canonical desktop toolbar and omnibox entrypoints. Aura must end
up with one canonical address-bar implementation that grows from these surfaces
instead of duplicating URL bar logic elsewhere.

## Extensions toolbar

- `chrome/browser/ui/views/extensions/extensions_toolbar_button.h`
- `chrome/browser/ui/views/extensions/extensions_toolbar_button.cc`
- `ToolbarView` integration through `ExtensionsToolbarDesktop`

Site-controls affordances should be layered on top of existing desktop toolbar
entrypoints, not a custom parallel runtime.

## Media controls

- `chrome/browser/ui/views/global_media_controls/media_toolbar_button_view.h`
- `chrome/browser/ui/views/global_media_controls/media_dialog_view.cc`
- `chrome/browser/ui/views/global_media_controls/*`

Helium already has a multi-session global media controls runtime. Aura should
reuse this as the source of truth and restyle/remap it into sidebar media
cards, not re-detect media independently.

## Split view / multi-content host

- `chrome/browser/ui/views/frame/multi_contents_view.h`
- `chrome/browser/ui/views/frame/multi_contents_view.cc`
- `chrome/browser/ui/views/frame/multi_contents_view_delegate.h`
- `chrome/browser/ui/views/frame/multi_contents_view_drop_target_controller.h`
- `chrome/browser/ui/views/frame/multi_contents_view_drop_target_controller.cc`
- `chrome/browser/ui/views/frame/multi_contents_view_mini_toolbar.h`
- `chrome/browser/ui/views/frame/multi_contents_view_mini_toolbar.cc`

Helium/Chromium already carries split-view content hosting. Aura split and
glance-like behavior should be integrated here where possible instead of
creating another content orchestration layer.

Important constraint:

- current Helium host is a real native split-content entry seam, but its
  visible model is narrower than Zen's split system
- Aura must therefore reuse Helium for native content hosting, drop targets,
  resize, and focus, while keeping Aura-owned split tree semantics, hover
  headers, context menu behavior, duplication rules, and `4`-member layout
  parity above it

## Side panel

- `chrome/browser/ui/views/side_panel/side_panel.h`
- `chrome/browser/ui/views/side_panel/side_panel.cc`

This is relevant for deciding what should remain a Chromium side panel versus
what becomes Aura-owned shell. The intent is to minimize duplication and keep
one clear owner for each surface.

## Patch policy

- Prefer adding thin Aura-owned integration hooks over scattering direct product
  logic across many Chromium files.
- If a feature can be expressed by reusing one of the entrypoints above, do not
  create a second owner.
- Aura shell should progressively replace or wrap visible desktop chrome, while
  Helium remains the runtime owner for tabs, profiles, extensions, media, and
  navigation.
