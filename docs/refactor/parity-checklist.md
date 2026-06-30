# Modernization Parity Checklist

Last updated: 2026-06-30

Use this checklist to prove behavior stayed stable after each small refactor
pass. Prefer the narrowest relevant slice first, then broaden only for risky
runtime or UI changes.

## Global Checks

- Build/list sanity: `xcodebuild -list -project Sumi.xcodeproj`.
- Full optimized-stack gate: `scripts/run_perf_regression.sh verify`.
- UI launch smoke when available: `scripts/run_perf_regression.sh ui-smoke`.
- Manual smoke for UI-risky changes: `docs/audit/live-smoke-matrix.md`.
- Clean-import/runtime-boundary guards:
  `scripts/check_safari_extension_clean_import.sh`,
  `scripts/check_userscript_hot_paths.sh`,
  `scripts/check_prepared_bundle_runtime_boundary.sh`, and
  `scripts/check_tracker_radar_import_boundary.sh`.

## Pass Mapping

| Refactor pass | Preserve | Required validation |
|---------------|----------|---------------------|
| Dead-code deletion | Current public API, persistence, selectors, resource names, notification names, and runtime registration paths. | Periphery + `rg` proof, app build, owner-specific tests. |
| WebView helper extraction | Visible WebView assignment, media stop, coordinator detach, split/multi-window behavior, destructive cleanup preparation. | WebView assignment/replacement tests, `BrowserConfigurationNormalTabTests`, compositor tests where touched. |
| Browser manager control-flow cleanup | Command routing, tab/window activation, startup restore, profile switch, sidebar/floating-bar actions. | `BrowserManagerRuntimeWiringTests`, startup/session tests, tab selection/open/close tests. |
| Tab manager helper extraction | Regular/pinned/essential/folder/split membership, structural batching, persistence, lazy restore. | `TabManagerStructuralPersistenceTests`, `TabManagerStructuralBatchingTests`, split and restore tests. |
| Permission refactor | Permission keys, prompt suppression, runtime controls, site settings, URL hub rows, system permission links. | Permission bridge/store/view-model tests and URL hub permission integration tests. |
| Safari extension cleanup | Native WKWebExtension load, profile isolation, site access, popup routing, native messaging, clean import. | Safari extension policy/runtime/native-messaging tests plus clean-import scripts. |
| Sidebar and drag/drop split | Native scroll feel, hover stability, hit testing, folder height, reorder/move behavior, favicon updates. | Sidebar drag/drop/context-menu tests and manual sidebar smoke. |
| URL hub split | Popover routing, permission rows, site data details, footer actions, tab-change dismissal. | `docs/url-hub/BEHAVIOR_PARITY.md` test slice and manual hub smoke. |
| Optional-module zero-cost cleanup | Disabled modules do not allocate observers, timers, WebViews, controllers, or background tasks. | `SumiPerformanceModularRegressionTests` and module-specific guard scripts. |

## Acceptance Rule

Every refactor PR should name:

- Current behavior being preserved.
- Structural improvement made.
- Exact validation command or manual scenario used.
- Public API or persistence surfaces intentionally left unchanged.
