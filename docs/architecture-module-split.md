# Sumi module split (Phase 7 scaffold)

# The app still builds as a single Xcode target (`Sumi`), now linked against two
# local SPM packages: `Packages/SumiDomain` and `Packages/SumiWebRuntime`. Full
# multi-target isolation remains the end state; until then,
# `scripts/check_domain_isolation_boundary.sh` enforces Foundation-only on
# remaining app-target domain files **and** rejects SwiftUI/AppKit/WebKit
# imports under `Packages/SumiDomain/Sources`, while
# `scripts/check_webruntime_isolation_boundary.sh` forbids SwiftUI and
# Tab/BrowserWindowState/BrowserManager type-edges under
# `Packages/SumiWebRuntime/Sources`.
#
# Intended dependency direction (compile-time once targets exist):
#
#   SumiDomain          — Foundation models, URL/site identity, permission keys
#        ▲
#   SumiWebRuntime      — WebKit, TabWebViewSession, WindowWebViewRegistry
#        ▲
#   SumiAppUI           — SwiftUI / AppKit chrome, BrowserManager composition
#
# Do not reverse edges. Domain must never import SwiftUI, AppKit, or WebKit.
# WebRuntime may use WebKit/AppKit/Foundation/Combine/OSLog; SwiftUI forbidden.
#
# Progress (U5 — first SumiDomain SPM package):
# - Local package `Packages/SumiDomain` (macOS 15.5, library product `SumiDomain`)
#   linked into the `Sumi` and `SumiTests` Xcode targets.
# - Closed 22-file Foundation cluster moved into the package (keyboard shortcut
#   enums, navigation value types, tab loading/surface owners, window projection
#   helpers, URL/site normalizers + PSL/punycode/classifier, permission key/
#   origin/request/security-context types, `SumiSurface`).
# - `public_suffix_list.dat` ships as a package resource (`Bundle.module`).
# - `RuntimeDiagnostics` edge in `SumiPublicSuffixList` replaced with OSLog so
#   the package stays closed.
# - `Tab.LoadingState` typealias retained in the app target (`Tab.swift`) over
#   public `TabLoadingState`.
# - Pure-domain unit tests remain in `SumiTests` (consume public API via
#   `import SumiDomain`); package has a small smoke test target.
#
# Progress (V5 — first SumiWebRuntime SPM package):
# - Local package `Packages/SumiWebRuntime` (macOS 15.5, depends on `SumiDomain`,
#   library product `SumiWebRuntime`) linked into `Sumi` and `SumiTests`.
# - Closed ownership/registry cluster moved in (15 production sources + package-
#   local diagnostics helper): `WindowWebViewRegistry`, `TabWebViewSession` /
#   store, deferred protected commands, tracking/cross-window/media-protection
#   owners, close-preparation + visible-tab plan + initial-document/shutdown
#   runtime contexts, and closed WK helpers (`SumiWebViewAudioState`,
#   `WKWebViewDrawsBackground`, `WKWebViewFullscreenPresentation`,
#   `SumiUserAgent`, `WebContentProcessDisplayNameProvider`).
# - AppKit/WebKit allowed; SwiftUI forbidden. App-target `RuntimeDiagnostics` /
#   `PerformanceTrace` edges replaced with package-local OSLog helpers.
# - Dropped from v1 (cannot close cleanly): `WebViewRuntimeContextStore` (needs
#   Visible/Browser contexts that edge `Tab`/`BrowserWindowState`),
#   `WebViewCompositorHandoffState` (edges `SumiWebViewContainerView`),
#   `SumiElementZapperSession` (SwiftUI overlay + page-script companions).
# - `@_exported import SumiWebRuntime` compatibility shim in the app target.
#
# Still blocked for Domain peel:
# - BrowserWindowState (SwiftUI environment / chrome state)
# - BrowserConfiguration (WebKit)
# - Tab itself (still a runtime-heavy class; accessors removal is separate)
# - SumiPermissionFailClosedMapper (pulls CoordinatorDecision)
# - Remaining DOMAIN_FILES allowlist entries (KeyboardShortcut model,
#   HistoryTypes, navigation responders, other Tab/Window owners)
#
# Still blocked for WebRuntime peel:
# - WebViewCoordinator.swift and Tab-parameterized owners
# - Visible/Browser runtime contexts (Tab / BrowserWindowState closures)
# - SumiWebViewContainerView / FocusableWKWebView / BrowserWebViewRoutingService
