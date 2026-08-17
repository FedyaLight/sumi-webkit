# Performance profiling and regression checks

Use this workflow for final optimization verification and for future regression checks. It keeps automation lightweight: a repeatable build/test harness plus human-driven Instruments traces anchored by coarse signposts.

## Fast regression harness

Run the optimized-stack smoke from the repository root:

```sh
scripts/run_perf_regression.sh verify
```

The `verify` command runs unsigned Debug and Release app builds, then the focused tests for:

- startup restore, structural persistence, and restore repair behavior
- structural batching and lookup batching
- runtime-state coalescing
- normal-tab WebKit configuration hot paths
- extension-rule lookup/cache attachment paths
- disabled-runtime startup boundaries
- local-generation memory and disabled-runtime guards

The harness intentionally uses method-level selectors for broad browser-configuration suites so the smoke stays focused on startup, normal-tab setup, extension-rule lookup, and memory boundaries.

Optional launch smoke:

```sh
scripts/run_perf_regression.sh ui-smoke
```

This uses the existing `SumiSmoke` UI-test scheme and requires a local macOS UI-automation environment that can bootstrap the Xcode runner. It is intentionally not part of `verify`.

## Recording traces

The harness can build Release and record signposted traces with stable names:

```sh
scripts/run_perf_regression.sh trace "Time Profiler" cold-launch-populated-store
scripts/run_perf_regression.sh trace "Allocations" tab-churn-structural-mutations
scripts/run_perf_regression.sh trace "Leaks" multi-window-switching
scripts/run_perf_regression.sh trace "Power Profiler" history-swipe-protected-flow
```

Traces are written to `.build/profiles/<date>-<scenario>-<template>.trace`. The script builds into `.build/performance/perf-derived-data` by default.

Useful environment overrides:

```sh
SUMI_PERF_TIME_LIMIT=120s scripts/run_perf_regression.sh trace "Time Profiler" cold-launch
SUMI_APP_SUPPORT_OVERRIDE=/tmp/sumi-perf-store scripts/run_perf_regression.sh trace "Allocations" populated-store
```

Quit any running Sumi instance before cold-launch traces.

## Instruments setup

Open the trace in Instruments and start with the Points of Interest or `os_signpost` lane. Filter for subsystem `com.sumi.browser` and category `PerformanceTrace`.

Use the same scenario name and template across before/after comparisons. Recommended templates:

- Time Profiler for CPU and main-thread work.
- Allocations for object churn and retained heap growth.
- Leaks for teardown and window/WebView cleanup.
- Power Profiler for energy-sensitive flows. This Xcode install lists `Power Profiler`, not `Energy Log`; treat it as the local energy profiling template.

## Scenario checklist and signposts

Cold launch with populated store:

- Prepare or reuse an app-support directory with multiple spaces, folders, regular tabs, pinned shortcuts, and a selected tab.
- Launch with `SUMI_APP_SUPPORT_OVERRIDE` if you do not want to use your real profile.
- Inspect `TabManager.loadFromStore`, `TabRestoreLoader.offMainRestore`, `TabManager.restoreApplyMainActor`, and `TabManager.restoreRepairFullReconcile`.
- `TabManager.restoreRepairFullReconcile` and `TabSnapshotRepository.fullReconcile` should appear only when restore repaired malformed current-format data.

Tab churn, move, folder, and space mutations:

- Open/close many tabs, move regular tabs across spaces, move tabs into/out of folders, and reorder pinned/space-pinned items.
- Inspect `TabManager.structuralTransaction`, `TabManager.structuralLookupBatch`, `TabManager.structuralPublish.coalesced`, `TabManager.persistIncrementalStructuralNow`, and `TabSnapshotRepository.incrementalStructuralPersistence`.
- Runtime-only title/URL churn should show `RuntimeStateCoalescer.coalescedBatchFlush` and `TabSnapshotRepository.runtimeStatePersistence`, not broad full reconciles.

Multi-window switching:

- Open at least two windows, switch active windows/spaces, and exercise split views.
- Inspect `VisibleWebViewRuntimeOwner.prepareVisibleWebViews`, `WebViewWindowCleanupOwner.cleanupWindow`, and `WebViewHiddenCloneEvictionOwner.evictHiddenWebViews`.
- Ordinary hidden-tab deactivation is owned by `TabSuspensionService` per-tab Memory Saver timers, not by a warm hidden buffer. `WebViewHiddenCloneEvictionOwner.evictHiddenWebViews` is internal hidden-clone/stale-WebView cleanup, for example a hidden clone of a tab that remains visible in another window.

History swipe and fullscreen-protected flows:

- Start and cancel history swipes, complete history swipes, and exercise fullscreen video teardown.
- Inspect `WebViewProtectedCommandOwner.enqueueDeferredProtectedCommand`, `WebViewProtectedCommandOwner.collapseDeferredProtectedCommand`, and `WebViewDeferredProtectedCommandExecutionOwner.dropDeferredProtectedCommand`.
- Queued commands should collapse where possible and drain after protection ends.

Extension-disabled vs extension-enabled startup/use:

- Record one trace with all extensions disabled and one with an enabled extension fixture.
- Inspect `ExtensionManager.init`, `ExtensionManager.lazyRuntimeDeferred`, `ExtensionManager.lazyRuntimeRequested`, `ExtensionManager.setupExtensionController`, `ExtensionManager.lazyRuntime`, `ExtensionManager.loadInstalledExtensions`, `ExtensionManager.loadEnabledExtension`, and `ExtensionManager.runtimeTeardown`.
- Disabled startup should load metadata without creating a controller. Enabled startup should defer runtime creation until attach/use requires it.

Space transition, omnibox, drag autoscroll, and import:

- Swipe repeatedly between populated spaces and inspect `SpaceTransition.total` plus `Theme.chromeRecipeBuild`; one source/target/settings combination should build one recipe while progress changes.
- Type, replace, and quickly cancel omnibox queries against a populated history store. Inspect `Omnibox.queryToPublish`, `Omnibox.localScore`, and `Omnibox.combinedScore`; scoring work should not appear on the main thread.
- Drag a pinned item through a long sidebar while autoscroll is active. Geometry updates should publish one scalar scroll-delta change per tick rather than rewrite every recorded frame.
- Preview Arc, Zen, and portable-file imports and inspect `Import.preview`; file reads, JSON/LZ4 work, and SQLite parsing should run off the main thread while the settings spinner remains active.
- With Boosts enabled, inspect `Boost.load` and `Boost.persist`. With Boosts disabled, neither interval nor a Boost disk worker should appear.

## Manual validation required

The harness catches obvious regressions and keeps the scenario workflow repeatable, but it does not replace human review in Instruments. Before shipping optimization changes, compare at least one trace per scenario for CPU, allocation growth, leaks, and power behavior.
