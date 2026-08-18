# Architecture Case Studies

These examples explain why Sumi has browser-specific seams that a conventional screen-oriented MVVM application would not need.

## Physical WebView Ownership

**Problem.** A durable page can be visible in more than one window, unloaded to save memory, or replaced during navigation recovery. Treating `Tab.webView` as global truth lets an old delegate callback mutate a newer residence or lets cleanup close a reused view.

**Decision.** `SumiWebRuntime` separates durable page identity from physical WebView residence. `WebViewSessionRepository` owns active placements and transition state, while commands validate the exact page, window, object identity, and revision immediately before mutation or cleanup.

**Why the extra machinery exists.** A dictionary from tab ID to WebView cannot represent two window residences or distinguish a retired object from a replacement with the same logical page. Exact leases and revisions turn those races into rejected stale work.

**Evidence.** The core implementation is in
[`SumiWebRuntime/Session`](../../Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/).
[`WebViewSessionArchitectureTests`](../../Packages/SumiWebRuntime/Tests/SumiWebRuntimeTests/WebViewSessionArchitectureTests.swift)
and
[`WebViewSessionRepositoryTests`](../../Packages/SumiWebRuntime/Tests/SumiWebRuntimeTests/WebViewSessionRepositoryTests.swift)
exercise ownership, replacement, cleanup, and stale-command behavior.

## Profile-Scoped Extension Runtime

**Problem.** Regular Browser Profiles must keep distinct account-bearing Website Data Stores. A shared WebKit extension context currently cannot provide a correct `cookies.onChanged` payload across those stores.

**Decision.** Keep `WKWebExtensionController`, contexts, permissions, storage, commands, and UI ordering profile-scoped. Share only installation packages and immutable, content-addressed extension resources. Private partitions use separate non-persistent contexts.

**Evidence.** The extension publication/admission tests cover profile isolation and lifecycle. Compatibility-specific behavior is summarized in [extensions.md](../extensions.md).

## Snapshot-Based Session Restoration

**Problem.** Live browser state contains AppKit windows, WebKit objects, delegates, tasks, and transient leases. Serializing that graph would restore stale identity and lifecycle state, while eagerly recreating every WebView would increase startup cost and memory use.

**Decision.** Persistence accepts value snapshots of browser-owned state. Restore transactions validate and repair the durable model, construct window state before the shell mounts, and materialize WebViews only when a page becomes live.

**Why a transaction is justified.** Import, profile retirement, and replace-style restore span multiple records and may be interrupted. Journals and pre-restore backups allow recovery without pretending each file or object write is independently authoritative.

**Evidence.** [`BrowserManagerStartupPersistenceTests`](../../SumiTests/BrowserManagerStartupPersistenceTests.swift),
[`WindowSessionRestoreTransactionTests`](../../SumiTests/WindowSessionRestoreTransactionTests.swift),
[`WindowSessionRestoreArchiveIntegrationTests`](../../SumiTests/WindowSessionRestoreArchiveIntegrationTests.swift),
and [`TabLazyRestoreCoordinatorTests`](../../SumiTests/TabLazyRestoreCoordinatorTests.swift)
cover ordering, repair, and lazy materialization.
