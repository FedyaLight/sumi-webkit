# Refactor Public API Contract

Last updated: 2026-06-30

Modernization passes must preserve source and persistence compatibility unless a
separate migration task explicitly changes this contract.

## Stable Surfaces

- Browser shell routing: `BrowserManager` command, window, tab, sidebar,
  floating-bar, URL-bar, zoom, history, profile, and WebView routing methods
  remain source-compatible for existing callers.
- Tab model and structure: `Tab`, `TabFolder`, split group, pinned, essential,
  folder, profile, and session-restore persistence shapes stay compatible.
- WebView ownership: `WebViewCoordinator` public entry points keep current
  behavior for visible assignment, cleanup, media protection, destructive cleanup
  preparation, and cross-window synchronization.
- Permissions: `SumiPermissionKey`, permission decision/policy types, site
  settings records, runtime-control results, and prompt bridge contracts keep
  their current semantics.
- Safari extensions: extension install/import/load, per-profile
  `WKWebExtensionController` isolation, site-access policy, action popups,
  options pages, native messaging, and diagnostic output remain Safari-native.
- Optional modules: disabled extensions, userscripts, content blocking, cleanup,
  memory saver, and energy saver remain lazy and avoid hidden runtime work.
- User data: bookmarks, history, downloads, profiles, sessions, permissions,
  site data policies, scripts, boosts, and extension stores keep existing
  persisted keys and migration behavior.

## Allowed Refactor Changes

- Move private helpers into narrowly named owner/resolver files when behavior is
  covered by the owner area's tests.
- Split view construction from state or presentation owners without changing
  layout, focus, hover, scroll, popover, keyboard, drag/drop, or animation
  behavior.
- Collapse duplicated private control flow inside a single ownership area.
- Delete private/internal code only after the evidence bar in
  `docs/refactor/modernization-audit.md` is met.

## Not Allowed Without A Migration Task

- Public method signature changes on manager, coordinator, bridge, permission,
  extension, tab, or model surfaces.
- Persistence key, schema, or archive-shape changes.
- Behavior changes to tab restore, launcher state, split layout, extension site
  access, permission prompting, WebView assignment, or sidebar drag/drop.
- Dependency upgrades, deployment-target changes, framework migrations, or CI
  enforcement changes.
- Site-specific, extension-specific, or product-specific bypasses in generic
  browser mechanisms.
