# Architecture Modernization Exec Plan

Last updated: 2026-07-03

## Baseline

- Starting score: 78/100.
- Target score: 95/100.
- Evidence baseline: `docs/refactor/modernization-audit.md`, `docs/architecture.md`, `xcodebuild -list -project Sumi.xcodeproj`.
- Current score estimate: 92/100 after adding CI architecture guardrails, persistence/WebView/sidebar boundary checks, clearer shell runtime dependency ownership, SwiftData schema contracts, TabManager composition owners, settings directory-store ownership, browser dependency boundary tightening, web page menu composition owners, Glance overlay runtime owners, updater Sparkle backend ownership, and import/export Zen parser ownership.

## Assumptions

- No repository-root `AGENTS.md` exists, so the provided thread instructions are the active instructions.
- Architecture slices should preserve user behavior unless explicitly documented otherwise.
- Guardrail work is the safest first slice because it has zero runtime cost and protects existing browser boundaries before ownership refactors.
- Full Xcode test runs may be expensive; each slice will run the narrowest meaningful command and document anything broader that remains unverified.

## Ranked Backlog

| Rank | Slice | Expected files | Risk | Verification |
| --- | --- | --- | --- | --- |
| 1 | Aggregate architecture boundary scripts and run them in CI. | `scripts/check_architecture_guardrails.sh`, `.github/workflows/architecture-guardrails.yml` | Low | `scripts/check_architecture_guardrails.sh` |
| 2 | Guard production SwiftData container construction behind `SumiStartupPersistence`. | `scripts/check_startup_persistence_boundary.sh`, `scripts/check_architecture_guardrails.sh` | Low | `scripts/check_startup_persistence_boundary.sh`; `scripts/check_architecture_guardrails.sh` |
| 3 | Strengthen SwiftData startup schema guardrails without changing store shape. | `SumiTests/SumiStartupPersistenceTests.swift` | Low | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/SumiStartupPersistenceTests` |
| 4 | Move required app-shell dependency checks to `BrowserShellRuntime`. | `Sumi/Managers/BrowserManager/BrowserShellRuntime.swift`, `Sumi/Managers/BrowserManager/BrowserManager.swift` | Low | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/BrowserManagerRuntimeWiringTests` |
| 5 | Guard WebView runtime context attachment ownership. | `scripts/check_webview_runtime_context_boundary.sh`, `scripts/check_architecture_guardrails.sh` | Low | `scripts/check_webview_runtime_context_boundary.sh`; `scripts/check_architecture_guardrails.sh` |
| 6 | Reduce BrowserManager responsibility by extracting or tightening one cohesive planning boundary. | `Sumi/Managers/BrowserManager*`, related owner tests | Medium | Focused `SumiTests/Browser*OwnerTests` for the touched owner |
| 7 | Clarify one WebKit capability/runtime ownership path. | `Sumi/Components/WebView*`, `Sumi/Models/Tab*`, WebView owner tests | Medium | Focused WebView or tab runtime tests for the touched path |
| 8 | Guard against direct BrowserManager SwiftUI environment coupling in sidebar/chrome UI. | `scripts/check_sidebar_browser_manager_boundary.sh`, `scripts/check_architecture_guardrails.sh` | Low | `scripts/check_sidebar_browser_manager_boundary.sh`; `scripts/check_architecture_guardrails.sh` |
| 9 | Narrow one sidebar/chrome state projection where it reduces dependency width. | `Sumi/Components/Sidebar/*`, `Navigation/Sidebar/*`, sidebar tests | Medium | Focused sidebar/chrome tests for the touched path |
| 10 | Add broader project guardrails only after the first slices show stable ownership boundaries. | `.github/workflows/*`, `scripts/*`, `SumiTests/*` | Medium | Script plus targeted Xcode tests |

## Stop Conditions

- A likely behavior regression appears and cannot be isolated safely.
- A required choice between two materially different architectures needs human product or design judgment.
- The same blocker repeats across three consecutive attempts.
- No safe architecture slice remains without broad rewrites or speculative abstraction.

## Current Progress

| Slice | Status | What changed | Verification | Remaining risk | Score estimate |
| --- | --- | --- | --- | --- | --- |
| Initial discovery | Complete | Confirmed `Sumi`, `SumiTests`, and `SumiUITests` targets plus shared schemes. No repo-local `AGENTS.md` was found. | `xcodebuild -list -project Sumi.xcodeproj` passed. | Subagent zone reports are still being collected. | 78/100 |
| Architecture guardrail CI | Complete | Added one local script that runs existing boundary scripts and a GitHub Actions workflow for PR/main protection. | `scripts/check_architecture_guardrails.sh` passed. | GitHub Actions runner execution is unverified until pushed. | 79/100 |
| Startup persistence boundary | Complete | Added a production scan that fails if SwiftData container, configuration, or schema construction moves outside `SumiStartupPersistence`. Wired it into the aggregate guardrail. | `scripts/check_startup_persistence_boundary.sh` passed; `scripts/check_architecture_guardrails.sh` passed. | Tests can still use in-memory containers directly; this slice only protects production runtime paths. | 80/100 |
| Shell runtime ownership | Complete | Moved required WebView coordinator, window registry, and shell content factory checks into `BrowserShellRuntime`; `BrowserManager` remains the public facade. | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/BrowserManagerRuntimeWiringTests` passed. | Precondition text changed for missing bindings; no runtime behavior change is intended. | 81/100 |
| WebView runtime boundary | Complete | Added a production scan that keeps WebView runtime context attach/detach calls inside `WebViewCoordinator` declarations and BrowserManager shell binding. Wired it into the aggregate guardrail. | `scripts/check_webview_runtime_context_boundary.sh` passed; `scripts/check_architecture_guardrails.sh` passed. | The guard protects ownership placement, not semantic correctness of each runtime context. | 82/100 |
| Sidebar environment boundary | Complete | Added a production UI scan that prevents direct `BrowserManager` SwiftUI environment injection and preserves projection/context ownership for sidebar/chrome views. Wired it into the aggregate guardrail. | `scripts/check_sidebar_browser_manager_boundary.sh` passed; `scripts/check_architecture_guardrails.sh` passed. | The guard blocks broad environment coupling; it does not reduce existing projected context width. | 83/100 |
| SwiftData schema contract | Complete | Strengthened startup persistence tests to assert the exact schema model order, uniqueness, migration schema version, and empty migration stages for V1. | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/SumiStartupPersistenceTests` passed. | This verifies the current V1 contract; future V2 work still needs a real migration stage. | 84/100 |
| TabManager space lifecycle owner | Complete | Moved space create/remove/reorder/rename/icon/activation logic from the `TabManager+SpaceLifecycle` extension into a composed `TabSpaceLifecycleOwner`; deleted the extension file. | Build passed; `SumiTests/TabSpaceCollectionStateOwnerTests`, `TabManagerStructuralPersistenceTests`, `TabManagerClearRegularTabsTests` passed; guardrails passed. | None known; facade signatures unchanged. | 85/100 |
| TabManager split group structure owner | Complete | Moved split group lookup, visual ordering, and structural mutation from the `TabManager+SplitGroups` extension into a composed `TabSplitGroupStructureOwner`; deleted the extension file. | Build passed; `SumiTests/SplitGroupTests` (80 tests) passed; guardrails passed. | None known; facade signatures unchanged. | 85/100 |
| Remaining TabManager extensions to owners | Complete | Replaced `TabManager+ProfilesUndo`, `+StartupRestore`, `+DragAndDrop`, and `+LauncherOwnership` with composed `TabProfileAssignmentOwner`, `TabLastSessionRestoreOwner`, `SidebarDragOperationRoutingOwner`, and `ShortcutPinCommandOwner`; folded closure-undo/bulk-close into `TabRemovalOwner`; gave `SidebarDragOperationContextValidator` its own file. No `TabManager+*.swift` extension files remain. | Build passed; `SidebarDragCurrentContextTests`, `TabManagerStructuralPersistenceTests`, `TabManagerStructuralBatchingTests`, `SplitGroupTests` (179 tests) passed; guardrails passed. | `TabManager.swift` is now a wide but thin facade (~2k lines of delegation and owner wiring); further narrowing means migrating call sites to owners directly. | 86/100 |
| Settings downloads directory store | Complete | Moved security-scoped downloads directory bookmark persistence out of `SumiSettingsService` into a composed `SumiDownloadsDirectoryStore`, and moved the standalone persisted settings value enums into `SumiSettingsValueTypes.swift`. | Build passed; `SettingsNavigationTests`, `PerformanceSettingsTests`, `DownloadManagerTests` passed; guardrails passed. | `SumiSettingsService` remains a broad preference bag; remaining seams are settings-surface URL mapping and energy-saver policy projection. | 87/100 |
| Browser dependency boundary tightening | Complete | Tightened broad browser/runtime dependencies by introducing narrower sidebar actions, permission inline cycle resolution, settings/content-blocking/favicons/extension stores, and explicit environment/context boundaries instead of direct manager reach-through. | `scripts/check_architecture_guardrails.sh` passed in subsequent final passes; `ce635a4ab` contains focused sidebar, permission, browser-window, and extension security tests for the slice. | This was a broad ownership pass; current follow-up did not rerun every focused test from that commit. | 88/100 |
| Web page menu composition owners | Complete | Split web page context menu orchestration, Sumi-owned menu sections, shared item creation, and menu text formatting into dedicated role types while leaving WebKit native item mutation in `SumiWebPageNativeMenuComposer`. `SumiWebPageMenuController.swift` dropped to ~326 lines. | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -only-testing:SumiTests/SumiWebPageMenuControllerTests -only-testing:SumiTests/TabRuntimeRoutingTests -only-testing:SumiTests/SumiNavigationResponderTests/testNativeContextMenuProbeConsumesChildWebViewRequestBeforeDynamicGlance` passed; guardrails passed. | Controller still owns action methods and validation, which is appropriate until call sites can target command owners directly. | 89/100 |
| Glance overlay runtime owners | Complete | Moved overlay visual styling, presentation state, promotion handoff, Escape-key command handling, and shield anchor view into dedicated role types. `GlanceOverlayController.swift` dropped from ~1148 to ~756 lines and gained direct keyboard owner tests. | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -only-testing:SumiTests/GlanceOverlayKeyCommandOwnerTests -only-testing:SumiTests/GlanceOverlayLayoutTests -only-testing:SumiTests/GlancePromotionCompletionOwnerTests -only-testing:SumiTests/GlanceManagerTests` passed; guardrails passed. | The controller still orchestrates open/close/promotion animation flow; further extraction should target animation choreography, not view-file splitting. | 90/100 |
| Updater Sparkle backend ownership | Complete | Moved production Sparkle backend, delegate, user driver, and appcast item mapping out of `SumiUpdaterService.swift` into dedicated role files. `SumiUpdaterService.swift` no longer imports Sparkle or Combine and dropped from ~997 to ~659 lines. Added an updater Sparkle boundary guardrail to keep framework coupling inside `SumiSparkle*` files. | `scripts/check_updater_sparkle_boundary.sh` passed; `scripts/check_architecture_guardrails.sh` passed; `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -only-testing:SumiTests/SumiUpdaterServiceTests` passed. | Updater service still owns notice state and store/view-model types in one file; future slices can separate update notice policy and About view projection if needed. | 91/100 |
| Import/export Zen parser ownership | Complete | Moved Zen import parsing, Mozilla LZ4 decoding, shared folder hierarchy repair, and import text normalization out of `SumiBrowserImportService.swift`. The service no longer imports Compression and dropped from ~968 to ~543 lines. Added an import/export boundary guardrail. | `scripts/check_import_export_boundaries.sh` passed; `scripts/check_architecture_guardrails.sh` passed; `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -only-testing:SumiTests/SumiImportExportTests` passed. | Arc parsing and file preview orchestration still remain in `SumiBrowserImportService.swift`; next import/export slice should extract those roles without splitting the service cosmetically. | 92/100 |

## Before/After Estimate

- Before: 78/100.
- After current slice estimate: 92/100.
- Target: 95/100 (standing instruction; honest composition only, no same-class extension-file splitting, owners named by real role).

## Ranked Next Targets (toward 95/100)

| Rank | Target | Size | Notes |
| --- | --- | --- | --- |
| 1 | `Sumi/ImportExport/SumiBrowserImportService.swift` | ~543 | Move Arc parsing and file preview/backup routing into real role types while keeping the service as import preview orchestration. |
| 2 | `Sumi/Components/WebsiteView/WebsiteCompositorView.swift` | ~1074 | Separate compositor state/geometry/input routing from SwiftUI rendering. |
| 3 | `Sumi/Managers/ExtensionManager/ExtensionInstallationFlowOwner.swift` | ~1046 | Split installation metadata/policy/progress orchestration without restoring broad manager coupling. |
| 4 | `Sumi/Managers/TabSuspensionService.swift` | ~993 | Separate suspension policy, scheduling, and tab mutation effects. |
| 5 | `Sumi/Components/Sidebar/URLBarHubPopover.swift` + `PinnedButtons/PinnedGrid.swift` | ~950 each | SwiftUI views; extract view models/state owners, not view splitting. |
| 6 | `Sumi/Updates/SumiUpdaterService.swift` remaining seams | ~659 | Separate update notice policy and About view projection from service state if further updater work is needed. |
| 7 | `BrowserManager.swift` facade narrowing | ~1167 | Mostly owner wiring already; migrate call sites to owners where it removes real dependency width. |
