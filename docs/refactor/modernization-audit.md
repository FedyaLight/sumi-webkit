# Sumi Modernization Audit

Last updated: 2026-06-30

This audit is the entry point for behavior-preserving modernization passes. It
tracks evidence before deletion or structural edits so each refactor can stay
small, reviewable, and reversible.

## Baseline Evidence

- Project shape: `xcodebuild -list -project Sumi.xcodeproj` reports the `Sumi`,
  `SumiTests`, and `SumiUITests` targets with `Sumi` and `SumiSmoke` schemes.
- Dead-symbol scanner: `.periphery.yml` is present and scoped to app sources
  while excluding tests and retaining Obj-C-accessible, Codable, SwiftUI preview,
  and protocol-parameter surfaces.
- Latest scanner run:
  `periphery scan --format csv --write-results .build/refactor/periphery.csv`
  completed with 622 candidate rows. The largest clusters are in
  `SidebarInteractiveItemView`, `BrowserManager`, `SumiUpdaterService`, `Tab`,
  `TabExtensionPageRuntimeOwner`, content-blocking owners, extension runtime
  owners, normal-tab user-content protocols, and sidebar drag state. These are
  triage inputs only, not deletion approval.
- Oversized files: the largest app files are concentrated in WebView, browser,
  tab, extension, permission, sidebar, Glance, settings, update, import/export,
  and content-blocking ownership areas.
- Stale runtime scan: production Swift has no active `ChromeMV3`, CRX installer,
  `sumiExternallyConnectableRuntime`, `SUMI_EC_PAGE_BRIDGE`,
  `setupExternallyConnectableBridge`, or `patchManifestForWebKit` hits. Remaining
  hits are docs or tests that guard removed behavior.
- Existing parity contracts: use `docs/performance/REFACTOR_PARITY_MATRIX.md`,
  `docs/url-hub/BEHAVIOR_PARITY.md`, `docs/audit/live-smoke-matrix.md`, and
  `docs/performance/MIGRATION_BACKLOG.md` before changing behavior-adjacent code.

## Current Hotspots

| Area | Current behavior | Modernization pressure | First safe pass |
|------|------------------|------------------------|-----------------|
| WebView lifecycle | `WebViewCoordinator` owns visible assignment, cleanup, cross-window sync, media protection, and destructive cleanup preparation. | Large file plus many extracted owners makes ownership boundaries hard to verify. | Extract or tighten pure planning helpers only when covered by WebView assignment/replacement tests. |
| Browser orchestration | `BrowserManager` remains the app-level hub with many extension files and owner delegates. | Central routing makes unrelated changes easy to couple. | Keep public routing stable; simplify duplicated private branches inside one owner at a time. |
| Tab structure | `TabManager` and persistence/launcher extensions preserve regular, pinned, essential, folder, split, and profile state. | High behavior density around restore and structural mutation. | Prefer pure lookup/planning extraction; validate with structural persistence/batching tests. |
| Permissions | Permission bridge, store, prompt, site settings, URL hub, and runtime-control code are already split but broad. | Many policy surfaces depend on shared key/decision semantics. | Preserve `SumiPermissionKey` and decision shapes; refactor row-building/view-model helpers only with targeted permission tests. |
| Extension runtime | Native Safari extension support uses `WKWebExtension` controllers, contexts, site access, popups, and native messaging. | Compatibility docs and guard tests contain historical removed-runtime references. | Keep Safari-native architecture; clean stale docs while preserving "do not restore" regression guards. |
| Sidebar and URL hub | UI behavior spans SwiftUI views, AppKit bridges, drag geometry, popovers, hover, and favicon refresh. | Large view/controller files obscure interaction contracts. | Split view construction from state/presentation only where parity tests and manual smoke cover behavior. |
| Optional modules | Extensions, userscripts, protection, cleanup, memory saver, and energy saver are intended to be lazy. | Eager observers/timers can creep into startup paths. | Audit disabled-module allocations before changing runtime wiring. |

## Deletion Evidence Bar

Do not delete production code unless all of these are true:

1. Periphery reports the symbol/file as unused using the repo `.periphery.yml`.
2. `rg` shows no production references, string-based registrations, selectors,
   notification names, KVC/KVO paths, Objective-C selectors, or resource names.
3. The owner area has a targeted build/test check listed in
   `docs/refactor/parity-checklist.md`.
4. The deletion does not alter public API or persistence shape unless a separate
   migration task explicitly approves it.

## Initial Candidates To Investigate

- Periphery candidates from `.build/refactor/periphery.csv`; treat every row as
  unproven until the deletion evidence bar is met. Most rows are instance
  variables and instance methods, so extra care is required around SwiftUI
  environment usage, Objective-C delegates, WebKit callbacks, Codable data, and
  diagnostics fields.
- Historical Safari extension compatibility references that describe already
  deleted Chrome MV3 / externally-connectable shims; keep only regression guards
  that prevent reintroducing those paths.
- Large pure helper clusters inside WebView assignment, tab close/open planning,
  permission row construction, URL hub presentation, and sidebar drag geometry.
- Repeated `NotificationCenter`, delay, and observer patterns in optional-module
  or UI code; do not replace broad lifecycle mechanisms without a dedicated
  migration task.

## Applied Cleanup Log

| Date | Change | Evidence | Validation |
|------|--------|----------|------------|
| 2026-06-30 | Deleted private `SumiBoostZapSelectorRow`; the active Zap button and context-menu removal path remain unchanged. | Periphery reported the private view as unused, and `rg` found no references outside its declaration. | `SumiBoostCSSBuilderTests` passed; `Sumi` Debug build passed. |

## Deferred Migrations

Keep these separate from modernization cleanup:

- `Tab` / `TabFolder` migration to `@Observable`.
- NotificationCenter tab lifecycle replacement with typed observation.
- `environmentObject(browserManager)` injection sweep.
- Full `BrowserManager` architecture split.
- DDG favicon page `MutationObserver` rewrite.
- Dependency upgrades, framework minimum changes, Sparkle/WebKit API migrations,
  or CI-wide Periphery enforcement.
