# Aura adapter contracts

Adapters are integration seams, not feature owners.

## Planned adapters

- `BrowserChromeAdapter`
  - `BrowserView` / `ToolbarView` / `LocationBarView` integration hooks
  - native sidebar and hub mounting points
  - address bar and compact-mode presentation hooks
  - transient surface anchor and focus handoff hooks
  - geometry-based drop hit testing and preview surfaces
- `BrowserWindowAdapter`
  - window activation
  - blank vs standard window mode
  - current space binding
  - restore entrypoints
- `TabModelAdapter`
  - current tabs and tab activation
  - split/glance integration hooks
  - reorder, split, layout-preset, empty-split, and unsplit verbs only
  - no keyboard policy and no compact-mode ownership
- `ProfileAdapter`
  - Chromium profile discovery and switching
- `ExtensionAdapter`
  - installed extension metadata
  - pinned extension action routing
- `MediaSessionAdapter`
  - upstream session metadata and control actions
- `ThemeAdapter`
  - browser-owned theme application hooks
