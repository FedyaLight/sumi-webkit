# Chrome MV3 Extension Runtime Spec

Status: planning only. No runtime implementation in this document.
Audit date: 2026-05-24.
Target: Chrome Manifest V3 extensions on top of system WebKit.

## Official References Checked

- Chrome Extensions API reference: https://developer.chrome.com/docs/extensions/reference/api
- Chrome extension service workers: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers
- Chrome extension service worker lifecycle: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
- Chrome content scripts: https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts
- Chrome scripting API: https://developer.chrome.com/docs/extensions/reference/api/scripting
- Chrome activeTab: https://developer.chrome.com/docs/extensions/develop/concepts/activeTab
- Chrome native messaging: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Chrome sidePanel API: https://developer.chrome.com/docs/extensions/reference/api/sidePanel
- Chrome offscreen API: https://developer.chrome.com/docs/extensions/reference/api/offscreen
- Apple WKWebExtensionController: https://developer.apple.com/documentation/webkit/wkwebextensioncontroller
- Apple WKWebExtensionContext: https://developer.apple.com/documentation/webkit/wkwebextensioncontext
- Apple WKWebViewConfiguration.webExtensionController: https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller
- Apple WKWebExtensionTab: https://developer.apple.com/documentation/webkit/wkwebextensiontab
- Apple WKWebExtensionWindow: https://developer.apple.com/documentation/webkit/wkwebextensionwindow
- Local Apple SDK headers checked at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/WebKit.framework/Headers/`.

The local WebKit headers confirm that `WKWebExtensionController` owns loaded extension contexts and must be attached through `WKWebViewConfiguration.webExtensionController`. `WKWebExtensionTab` also requires its tab web view to use a configuration with the same controller. That makes Sumi's "extensions disabled" invariant concrete: no controller on normal browsing configurations means no WebKit extension context can attach.

Chrome's official MV3 lifecycle documentation states that extension service workers are event-driven and unloadable. Current Chrome behavior terminates service workers after idle time, long-running requests, and long-delayed fetch responses; Sumi should follow that policy shape even if WebKit's exact implementation differs.

## Problem Statement

Sumi currently has an optional extension subsystem that mixes reusable WebKit extension engine pieces with Safari-extension product assumptions. Sumi is not published yet, so there is no legacy user migration requirement. The next runtime should be Chrome MV3 compatible, performance-first, and optional. It should use system WebKit where appropriate, but the product model must be Chrome MV3 only:

- no MV2 support
- no Safari-extension compatibility layer
- no `.app` or `.appex` Safari extension install flow
- no permanent hidden MV2-style background page
- no runtime cost when extensions are disabled

This document defines the foundation for a future runtime. It does not implement the runtime.

## Goals

- Define a concrete optional module boundary for Chrome MV3 extension support in Sumi.
- Separate WebKit engine requirements from Safari-extension product assumptions.
- Preserve reusable Sumi infrastructure where it already supports an optional zero-runtime-cost model.
- Delete unpublished Safari-extension product surfaces instead of migrating them.
- Define a conservative Chrome MV3 capability matrix and unsupported API reporting path.
- Treat password-manager-class extensions as a first-class compatibility target.
- Specify an event-driven service worker lifecycle aligned with Chrome MV3.
- Define the future install pipeline around original bundles, generated bundles, manifest rewrite, wrappers, shims, native bridge, and diagnostics.

## Non-Goals

- Implementing the runtime.
- Supporting MV2 manifests, background pages, or event pages.
- Supporting Safari `.app` or `.appex` extension discovery/install.
- Migrating current unpublished Safari-extension records.
- Restoring DuckDuckGo legacy systems unless a future task proves a need.
- Adding broad `@MainActor` annotations or `@unchecked Sendable` shortcuts.

## Product Invariants

- Sumi is performance-first.
- Extensions are optional.
- Chrome Manifest V3 only.
- When extensions are disabled:
  - no `WKWebExtensionController`
  - no `WKWebExtensionContext`
  - no extension JS injection
  - no service-worker wakeups
  - no native messaging process or port state
  - no hidden extension runtime cost
- An inert module gate, settings toggle, and empty UI projection may exist while disabled, but they must not create a controller, context, generated bundle, extension user scripts, or background worker.
- Auxiliary/helper web views must not participate by default.
- Preview and mini-window surfaces require explicit future justification before extension support.

## User Scenarios

- A user installs a Chrome MV3 password manager extension, unlocks from the action popup, and fills a login form in a normal tab without enabling extensions in helper web views.
- A user disables extensions and sees no extension contexts, content scripts, service-worker wakes, native messaging ports, or controller attachment in future diagnostics.
- A developer installs an unpacked MV3 fixture and receives precise unsupported API diagnostics before runtime load.
- A user opens Sumi's settings without enabling extensions; the settings surface can describe the optional feature without loading the runtime.
- A normal tab can participate in extensions when the module is enabled; favicon downloads, preview helpers, launcher metadata, and other auxiliary surfaces do not.

## Acceptance Criteria

- The runtime gate can be inspected in tests: disabled means no `WKWebExtensionController`, no loaded contexts, no injected extension scripts, and no background wake events.
- MV2 manifests are rejected before generated-bundle creation.
- Safari `.app` and `.appex` installation paths are deleted from product UI and install code.
- Every supported, shimmed, deferred, or unsupported Chrome API has an entry in the capability registry and reporter.
- Password-manager fixture tests cover frame injection, controlled input fill, popup unlock, long-lived ports, native messaging, and service worker wake/unload behavior.
- Normal browsing web views are the only default participating surface.
- Auxiliary, metadata-only, preview, and mini-window surfaces are excluded unless a future spec explicitly opts them in.

## Repo Search Evidence

Searches used `rg` over the repository for Safari/WebExtension terms, WebKit extension APIs, user-script bridge terms, native messaging, settings toggles, and `WKWebViewConfiguration` creation. The main findings are below.

### Current Extension Runtime and Product Surfaces

- `Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift` is already the optional gate. It creates `ExtensionManager` lazily only when enabled and needed, and tears down loaded runtime state on disable.
- `Sumi/Managers/ExtensionManager/ExtensionManager.swift` owns the current runtime: `WKWebExtensionController`, loaded contexts, tab/window adapters, background task tracking, native ports, data stores, and metadata.
- `Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift` attaches runtime state to profile/window/tab lifecycles and builds `WKWebExtensionController.Configuration`.
- `Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift` scans `/Applications` and `~/Applications` for Safari `.appex` bundles and supports `.app`, `.appex`, and directory install paths.
- `Sumi/Managers/ExtensionManager/ExtensionManager+ManifestPatching.swift` rewrites manifests and resources for WebKit compatibility, including MV2 background pages/event pages and MV3 service-worker wrappers.
- `Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift` maps WebKit delegate callbacks for action popups, permissions, tabs/windows, native messaging, and options pages. It also contains `SafariNativeMessageRouter`.
- `Sumi/Managers/ExtensionManager/ExtensionBridge.swift` exposes Sumi tabs/windows as `WKWebExtensionTab` and `WKWebExtensionWindow`.
- `Sumi/Managers/ExtensionManager/NativeMessagingHandler.swift` contains native host process lookup and framed stdio bridge code.
- `Sumi/Managers/ExtensionManager/ExtensionRuntimeResources/*.js` contains runtime compatibility, externally_connectable, and content-script guard resources.
- `Sumi/Components/Extensions/ExtensionActionView.swift` is the current extension action strip.
- `Sumi/Components/Settings/SettingsView.swift` exposes "Safari Extensions" discovery, install, enable/disable, action visibility, and uninstall flows.
- `Sumi/Components/Settings/SettingsUtils.swift` names the settings subpane `safariExtensions`.
- `App/SumiCommands.swift` adds "Install Extension..." and "Manage Extensions..." commands.
- `Sumi/Services/BrowserExtensionSurfaceStore.swift` projects the live Safari/WebExtension runtime into UI.
- `Sumi/Models/Extension/ExtensionModels.swift` persists Safari source kinds, trust summaries, MV2/MV3 background models, source bundle IDs, containing app bundle IDs, and appex bundle IDs.

### WebKit Engine and Configuration Surfaces

- `Sumi/Models/BrowserConfig/BrowserConfig.swift` centralizes normal and auxiliary `WKWebViewConfiguration` creation.
- `Sumi/Models/BrowserConfig/BrowserConfig.swift` only copies `webExtensionController` for `.extensionOptions` auxiliary configurations today.
- Chrome MV3 DEBUG normal-tab attachment diagnostics must not count that legacy `.extensionOptions` copy as normal-tab attachment. TODO: isolate or replace the extension-options copy when a future extension-owned UI host is designed.
- `Sumi/Models/Tab/Tab+WebViewRuntime.swift` creates normal tab web views and calls `extensionsModule.prepareWebViewConfigurationForExtensionRuntime(...)`.
- `Sumi/Models/Tab/Tab+WebViewRuntime.swift` calls `prepareWebViewForExtensionRuntime(...)` after normal tab web view creation.
- `Sumi/Models/Tab/Tab+UIDelegate.swift` and `Sumi/Managers/BrowserManager/SumiPopupHandlingNavigationResponder.swift` create new web views/popups from WebKit UI delegate flows.
- `Sumi/Components/Browser/MiniWindowWebView.swift` uses auxiliary `.miniWindow` configuration.
- `Sumi/Services/FaviconDownloader.swift` uses auxiliary `.faviconDownload` configuration.
- `Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift` creates extension options windows using auxiliary `.extensionOptions`.

### User Scripts and Message Brokers

- `Sumi/UserScripts/SumiUserScriptMessageBroker.swift`, `Sumi/UserScripts/SumiUserScriptMessageHandlerRegistry.swift`, and `Sumi/UserScripts/SumiNormalTabUserScripts.swift` provide Sumi's own user-script broker and registration path.
- Current searches did not find a BrowserServicesKit user-script message broker in `Vendor/DDG/BrowserServicesKit`; extension-related bridging is local to Sumi.
- `Sumi/Managers/ExtensionManager/ExtensionManagerSupport+BrokerSubfeatures.swift` uses the local broker for externally_connectable support.

### DuckDuckGo Vendor URL Classification

- `Vendor/DDG/URLPredictor/Sources/URLPredictor/Classifier.swift` still treats `webkit-extension` and `x-safari-https` schemes as valid URL-like protocols.
- `Vendor/DDG/URLPredictor/Tests/URLPredictorTests/ClassifierTests.swift` has tests for those schemes.

## Preserve / Delete / Redesign / Risky

### Preserve

| Area | Evidence | Why preserve |
| --- | --- | --- |
| Optional gate | `Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift` | Already models lazy runtime creation, enable/disable, empty UI projection, and runtime teardown. Rename/refine around Chrome MV3. |
| Browser config centralization | `Sumi/Models/BrowserConfig/BrowserConfig.swift` | Clear place to enforce which web views can receive `webExtensionController`. |
| Normal tab attach hooks | `Sumi/Models/Tab/Tab+WebViewRuntime.swift` | Correct future hook for eligible normal browsing web views. |
| Tab/window adapter concept | `Sumi/Managers/ExtensionManager/ExtensionBridge.swift` | Required by WebKit through `WKWebExtensionTab` and `WKWebExtensionWindow`; rename away from Safari language. |
| Native messaging process bridge concept | `Sumi/Managers/ExtensionManager/NativeMessagingHandler.swift` | Password managers often need native messaging. Keep the concept, redesign safety boundaries and permissions. |
| User-script broker infrastructure | `Sumi/UserScripts/*.swift` | Useful Sumi infrastructure for controlled script registration and message handling. Extension scripts must remain absent while disabled. |
| Extension options surface concept | `Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift` | MV3 options pages still need a host, but not Safari install UI. |
| Surface store concept | `Sumi/Services/BrowserExtensionSurfaceStore.swift` | UI can observe an empty projection without loading runtime. Rename from Safari/WebExtension assumptions. |
| Existing disabled-runtime tests | `SumiTests/BrowserConfigurationNormalTabTests.swift`, `SumiTests/SumiPerformanceModularRegressionTests.swift` | These tests encode the performance invariant and should be expanded. |

### Delete

| Area | Evidence | Delete reason |
| --- | --- | --- |
| Safari `.app`/`.appex` discovery | `Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift` | Chrome MV3 install pipeline should not scan Safari app extensions. |
| Safari extension install UI | `Sumi/Components/Settings/SettingsView.swift`, `App/SumiCommands.swift` | Product surface is Safari-specific and unpublished. |
| Safari source/trust fields | `Sumi/Models/Extension/ExtensionModels.swift` | No migration requirement; replace with Chrome bundle/install provenance. |
| MV2 background support | `Sumi/Models/Extension/ExtensionModels.swift`, `Sumi/Managers/ExtensionManager/ExtensionUtils.swift`, `ExtensionManager+ManifestPatching.swift` | Product invariant is MV3 only. |
| `SafariNativeMessageRouter` | `Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift` | Safari-specific workaround/product command router. |
| Safari-named settings subpane | `Sumi/Components/Settings/SettingsUtils.swift` | Rename to Chrome MV3 extensions or browser extensions. |
| Safari scheme assumptions in product code | `ExtensionManager.swift`, `ExtensionManager+ManifestPatching.swift` | Generated Chrome MV3 runtime should not expose Safari compatibility as product behavior. |
| `x-safari-https` URL classification if unused | `Vendor/DDG/URLPredictor/...` | Needs follow-up before vendor edit, but should not be part of Sumi extension product support. |

### Redesign

| Area | Evidence | Redesign target |
| --- | --- | --- |
| Manifest patching | `ExtensionManager+ManifestPatching.swift` | Replace Safari/WebKit compatibility patching with MV3 generated-bundle normalizer and capability reporter. |
| Runtime compatibility JS | `ExtensionRuntimeResources/webkit_runtime_compat*.js` | Keep only explicit Chrome API shims backed by capability registry. |
| Externally connectable bridge | `ExtensionManager+ExternallyConnectable*.swift`, JS resources | Rebuild as a general MV3 runtime messaging bridge with origin/extension permission checks. |
| Permission delegate | `ExtensionManager+ControllerDelegate.swift` | Replace silent-deny placeholder behavior with explicit permission broker and activeTab grant model. |
| Action UI | `Sumi/Components/Extensions/ExtensionActionView.swift` | Rebuild around Chrome `action`, popup lifecycle, pinned/hidden state, and password-manager unlock UX. |
| Install storage | `ExtensionManager+Store.swift`, `ExtensionModels.swift` | Replace Safari source model with original bundle store, generated bundle store, normalized manifest, and unsupported API report. |
| Background task tracking | `ExtensionManager.swift`, `ExtensionManager+Profiles.swift` | Replace loaded/not-loaded state with MV3 wake reason, idle, unload, timeout, and diagnostics policy. |
| Content-script guard | `ExtensionManager+ManifestPatching.swift`, `selective_content_script_guard.js` | Rebuild around Chrome MV3 matching, `all_frames`, `match_about_blank`, isolated world, and frame provenance. |

### Risky / Unclear

| Area | Evidence | Follow-up |
| --- | --- | --- |
| WebKit MV3 service worker unload behavior | WebKit headers confirm contexts/controllers, not Chrome-equivalent lifecycle details | Build fixtures to verify wake/unload, idle, and long-lived port behavior. |
| `WKWebExtension` API coverage | Apple docs and headers expose APIs but not Chrome parity | Capability matrix must start conservative and be proven with fixtures. |
| Cookie API parity | Chrome `cookies` API semantics may not map cleanly to `WKWebsiteDataStore` | Defer until a tested privacy/profile design exists. |
| Declarative net request parity | WebKit content rule lists may not match Chrome DNR semantics | Defer; avoid claiming adblock-class compatibility until proven. |
| Native messaging concurrency | `NativeMessagingHandler.swift` currently contains `@unchecked Sendable` types | Redesign without adding new unchecked sendability shortcuts. |
| Preview/Glance participation | `Sumi/Managers/GlanceManager/GlanceManager.swift` creates preview `Tab` instances that can later create normal web views | Future eligibility gate must exclude previews unless explicitly opted in. |
| Vendor DDG schemes | `Vendor/DDG/URLPredictor` allows extension-like schemes | Verify whether any non-extension URL prediction code still needs these schemes before deleting. |

## WKWebViewConfiguration Surface Inventory

| Surface | Current evidence | Future extension applicability |
| --- | --- | --- |
| Normal tabs | `BrowserConfig.normalTabWebViewConfiguration(...)`, `Tab+WebViewRuntime.makeNormalTabWebView(...)` | May participate when extensions module is enabled, profile is eligible, and tab has grants. |
| Pinned tabs / Essentials live runtime | `TabManager+LauncherOwnership.swift` attaches live shortcut tabs; live tabs use normal tab runtime paths | Live browsing web views may participate only when they are real normal browsing tabs. |
| Pinned/Essentials launcher identity metadata | `ShortcutPin.swift`, `TabManager+LauncherProjection.swift` | Must not be affected. Metadata-only launcher identity has no extension runtime. |
| Peek/Glance previews | `GlanceManager.swift`, `GlanceManager+Lifecycle.swift` create preview tabs and promote them | Should not participate by default. Promotion to a normal tab may enable runtime only after eligibility is recalculated. |
| Mini windows | `MiniWindowWebView.swift` uses auxiliary `.miniWindow` | Should not participate by default; needs explicit future justification. |
| Extension options pages | `ExtensionManager+UI.swift` uses auxiliary `.extensionOptions` and current context configuration | May participate only as extension-owned UI, never as general auxiliary browsing. |
| Favicon downloads | `FaviconDownloader.swift` uses auxiliary `.faviconDownload` with JavaScript disabled | Must never participate. |
| Popup/new-window delegate surfaces | `Tab+UIDelegate.swift`, `SumiPopupHandlingNavigationResponder.swift` | Only participate when they become normal browsing tabs/windows. WebKit-created helper views should be filtered. |
| Cloned/preview web views | `WebViewCoordinator.swift` calls `tab.makeNormalTabWebView(...)` | Must be classified by surface eligibility, not only by using normal tab factory. |

## Target Architecture

The future module should be a package-like optional boundary, even if it starts inside the app target:

`SumiExtensionsModule` -> `ChromeMV3ProfileHost` -> install store, generated bundles, capability registry, tab/window adapters, permission broker, UI hosts, and native bridge.

| Component | Responsibility | Lifecycle owner | Actor/threading boundary | Exists when disabled |
| --- | --- | --- | --- | --- |
| Extension module gate | Own enabled flag, lazy creation, teardown, diagnostics summary | `BrowserManager` | Main actor facade only; no runtime work | Yes, inert facade only |
| Profile host | Per-profile controller/context ownership and web view eligibility | Extension module | Main actor for WebKit; background actors for file/index work | No |
| Install store | Persist original bundle metadata, normalized manifest, generated bundle path, unsupported API report | Profile host or app-level extension store | Background file actor plus main actor publish | No active store handle; existing records may be listed lazily without runtime |
| Manifest validator/normalizer | Reject non-MV3, normalize Chrome manifest, compute permissions, API usage, content script plan | Install pipeline | Background actor, pure data | No |
| Generated bundle writer | Create generated WebKit-compatible bundle with rewritten manifest, service-worker wrapper, JS shim, native bridge resources | Install pipeline | Background file actor | No |
| Capability registry | Declare nativeWebKit/shim/nativeHost/unsupported/deferred/needsVerification by API and subfeature | Install pipeline and runtime bridge | Immutable data, thread-safe value types | Static data may exist; no runtime |
| Tab/window adapters | Map Sumi normal tabs/windows to `WKWebExtensionTab`/`WKWebExtensionWindow` | Profile host | Main actor because WebKit UI APIs are UI actor | No |
| Web view eligibility gate | Decide whether a `WKWebViewConfiguration` may receive `webExtensionController` | Browser config/profile host | Main actor decision, pure inputs | Static policy only; no controller |
| Action/popup/options hosts | Render `chrome.action` UI, popups, options pages, extension-owned web views | Extension UI host | Main actor | No |
| Permission broker | Host permissions, `activeTab`, optional permissions, user prompts, per-tab grants | Profile host | Main actor for prompts; value snapshots for matching | No |
| Native messaging bridge | Validate hosts, start/stop processes, frame messages, connect ports | Profile host | Dedicated background actor/process manager; main actor only for lifecycle notifications | No |
| Runtime messaging bridge | `runtime.sendMessage`, `runtime.connect`, content-script/page/native routing | Profile host | Main actor for WebKit calls; background for timeout bookkeeping | No |
| Service-worker lifecycle coordinator | Wake reason tracking, idle/unload policy, request timeouts, diagnostics | Profile host | Main actor for WebKit; clock/timer actor for policy | No |
| sidePanel host | Future host for Chrome side panel API | Extension UI host | Main actor | No |
| offscreen host | Future bounded invisible document host if justified | Profile host | Main actor, strict timeout policy | No |
| identity host | Future OAuth/identity API host | Profile host | Main actor for UI; background for token storage | No |
| Compatibility reporter | Install-time and runtime unsupported API diagnostics | Install pipeline/profile host | Value types plus background log writer | Static reporter type may exist; no runtime |
| Test fixtures | MV3 fixture bundles for API matrix and password-manager flows | Test target | Test-only | No |

## Disabled State Contract

The disabled state must be observable and testable:

- `SumiExtensionsModule.isEnabled == false`.
- `SumiExtensionsModule.hasLoadedRuntime == false`.
- No `ExtensionManager` or future `ChromeMV3ProfileHost` is created.
- No `WKWebExtensionController.Configuration` is created.
- No `WKWebExtensionController` is assigned to normal tab configurations.
- No `WKWebExtensionContext` is loaded.
- No extension-generated user scripts are added to `SumiUserScriptMessageHandlerRegistry`.
- No service-worker wake timers or runtime messaging queues exist.
- No native messaging process is launched.
- Extension UI projections are empty and do not force runtime creation.

## Capability Matrix v1

Statuses:

- `nativeWebKit`: WebKit appears to provide a relevant primitive; still fixture-test it.
- `shim`: generated JS shim can provide Chrome-compatible surface over WebKit/Sumi primitives.
- `nativeHost`: Sumi must implement native behavior outside WebKit.
- `unsupported`: reject/report for v1.
- `deferred`: not v1, may be supported later.
- `needsVerification`: official docs/headers are insufficient; prove with fixtures before claiming.

| Chrome MV3 API | Status | v1 position |
| --- | --- | --- |
| `runtime` | nativeWebKit + shim + needsVerification | Support core identity, URL, message, connect, lifecycle events needed by password managers. Verify exact WebKit event behavior. |
| `storage` | nativeWebKit + shim + needsVerification | Support `local`; verify `session` and `sync` behavior. `sync` may be local-only or deferred unless product policy says otherwise. |
| `tabs` | nativeWebKit + nativeHost | Support active tab metadata, create/update/query/remove where mapped to Sumi normal windows/tabs. |
| `scripting` | nativeWebKit + nativeHost + needsVerification | Support MV3 content script registration/execution only after frame and world behavior is proven. |
| `action` | nativeWebKit + nativeHost | Support action icon/title/badge/popup and click. |
| `permissions` | nativeHost + needsVerification | Implement explicit broker for host and optional permissions. |
| `activeTab` | shim + nativeHost | Implement temporary per-tab grants on user gesture. |
| `contextMenus` | nativeHost + deferred | Needed by many extensions, but not password-manager critical for v1. |
| `cookies` | deferred + needsVerification | Do not claim parity until `WKWebsiteDataStore` mapping and profile/privacy rules are designed. |
| `alarms` | nativeHost + shim | Implement bounded event wake scheduler when service-worker lifecycle exists. |
| `webNavigation` | nativeHost + needsVerification | Map Sumi/WebKit navigation events conservatively. |
| `webRequest` | unsupported/deferred | No blocking webRequest in v1. Consider observe-only later if WebKit permits. |
| `declarativeNetRequest` | deferred + needsVerification | Potentially map subsets to content rule lists later, but Chrome parity is non-trivial. |
| `nativeMessaging` | nativeHost | First-class for password-manager compatibility, with strict host validation and port lifecycle. |
| `sidePanel` | deferred + nativeHost | Add only with explicit UI spec. |
| `offscreen` | deferred + needsVerification | Add only if a bounded invisible document host is justified. Never use it as a persistent background. |
| `identity` | deferred + nativeHost | OAuth/token flows need product and privacy design. |
| `debugger` | unsupported | Not v1. |
| `devtools` | unsupported | Not v1. |
| `enterprise` | unsupported | Not a Sumi consumer target. |
| `i18n` | shim | Reuse manifest locale parsing idea from `ExtensionUtils.localizedString(...)`; expose Chrome-compatible lookups. |
| `notifications` | deferred + nativeHost | Could map to Sumi notifications later; not v1 unless fixtures require it. |
| `downloads` | deferred + nativeHost | Needs download manager permission and UX design. |
| `bookmarks` | deferred + nativeHost | Needs Sumi bookmarks API design. |
| `history` | deferred + nativeHost | Needs privacy model and Sumi history API design. |

## Password-Manager Compatibility Target

Password managers are a v1 compatibility target, not an afterthought. A fixture suite should model Bitwarden/1Password-style behavior without depending on proprietary extension code.

Acceptance tests:

- Content scripts inject at `document_start`, `document_end`, and `document_idle` according to manifest rules.
- `all_frames` injects into same-origin and permitted cross-origin iframes.
- `about:blank`, `about:srcdoc`, and dynamically-created frames follow Chrome `match_about_blank` and parent-origin rules.
- Isolated world scripts can inspect and modify form fields without polluting page globals.
- Page-world injection is available only when explicitly needed and permissioned.
- React, Vue, and Angular controlled inputs update using the page's native value setter where needed.
- Autofill dispatches the events expected by modern forms: `input`, `change`, and focus/blur behavior as required by the fixture.
- Overlay UI can anchor near username/password inputs, follow layout/scroll/zoom changes, and avoid appearing in helper web views.
- `runtime.sendMessage` and `runtime.connect` work from content scripts to the service worker.
- Long-lived ports work for active fill/unlock flows but do not keep the worker alive indefinitely after the user-visible flow ends.
- Native messaging connects to an allowed host, exchanges framed messages, handles host exit, and denies unknown hosts with diagnostics.
- The action popup can unlock the extension, update action state, and resume a fill flow.
- `storage.local` and v1-approved session state survive worker unload/reload according to Chrome MV3 expectations.
- A service worker wakes for a fill action and unloads after idle/timeout policy allows it.
- `activeTab` grants are created only from valid user gestures and expire on tab/navigation boundaries.
- Host permission checks block ungranted page access and report actionable diagnostics.

## Service-Worker Lifecycle Policy

Sumi's policy should align with Chrome MV3: event-driven, unloadable, no permanent background page.

Wake events:

- extension install/update/startup events when the profile host is active
- `runtime.sendMessage` and `runtime.connect`
- content-script messages
- action click and popup events
- tab/window/navigation events for APIs granted to the extension
- alarms
- native messaging connect/message events
- permission grant/revoke events
- context menu events if that API is enabled

Idle and unload:

- The service worker is unloadable whenever it has no active event, no active bounded port operation, and no pending permitted native request.
- Target Chrome's documented shape: idle termination around 30 seconds, hard timeout around 5 minutes for a single operation, and short network/fetch response timeout behavior where applicable.
- If WebKit's runtime keeps a worker alive longer, Sumi must not add extra retention. If WebKit unloads sooner, Sumi must persist state and retry only in Chrome-compatible ways.
- Sumi must never create a hidden persistent `WKWebView` background page to emulate MV2.
- Sumi must never keep `WKWebExtensionContext` loaded solely to emulate a permanent background.
- Sumi must never revive MV2 background pages or event pages.

Operation bounds:

- Bridge request timeout: default 30 seconds unless an API has a documented longer Chrome-compatible window.
- Hard operation timeout: default 5 minutes for a single wake event.
- Long-lived ports: allowed for active user-visible workflows or native messaging sessions; must close on tab close, extension disable, host exit, explicit disconnect, or bounded idle policy.
- Alarms/events: wake the service worker for event delivery, then release it after event completion.
- State persistence: extension state must live in WebKit/extension storage or Sumi's approved storage abstraction, never in Swift singletons that assume a permanent worker.
- Diagnostics: record wake reason, extension id, profile id, duration, pending requests, timeout, unload reason, unsupported API hits, and native host failures.

## Install Pipeline v1

The install pipeline should be deterministic and auditable:

1. Original bundle intake
   - Accept Chrome MV3 CRX/zip/unpacked directory in a future task.
   - Preserve the original bundle read-only with hash, source type, install time, extension id, and manifest snapshot.
   - Reject `.app`, `.appex`, MV2, missing manifest, invalid service worker path, unsupported manifest keys that cannot be ignored, and unsafe paths.

2. Manifest validation and normalization
   - Require `manifest_version: 3`.
   - Normalize extension id, name, version, permissions, host permissions, content scripts, action, options page, web accessible resources, background service worker, externally connectable, and native messaging requirements.
   - Produce a capability report before runtime load.

3. Generated bundle creation
   - Write a generated WebKit-compatible bundle separate from the original.
   - The generated bundle may include rewritten manifest, service-worker wrapper, JS shim, native bridge scripts, content-script guard, locale assets, and compatibility metadata.
   - Generated output is disposable and can be rebuilt from original bundle plus Sumi generator version.

4. Service-worker wrapper
   - Inject only MV3-compatible wrapper code.
   - No MV2 background page or event page generation.
   - Wrapper records wake diagnostics and routes supported Chrome APIs through capability registry.

5. JS shim
   - Provide `chrome.*` compatibility only for APIs in the capability matrix.
   - Unsupported APIs must fail predictably and report to the compatibility reporter.

6. Native bridge
   - Provide bounded message routing for runtime messaging, native messaging, activeTab grants, permissions, and action/popup state.
   - Bridge startup must require an enabled module and eligible profile host.

7. Runtime load
   - Create `WKWebExtensionController` only after an enabled extension requires it.
   - Load `WKWebExtensionContext` only for enabled extensions in eligible profiles.
   - Attach controller only to eligible normal browsing configurations or extension-owned options/popup hosts.

8. Disable/uninstall
   - Disable unloads contexts, releases controller if no enabled extensions remain, closes ports, removes extension user scripts, and clears runtime diagnostics queues.
   - Uninstall removes generated bundle and record; original bundle removal follows product policy.
   - No legacy migration path is required.

## Phased Implementation Plan

1. Deletion prep
   - Delete Safari `.app`/`.appex` discovery and install UI.
   - Delete MV2 manifest/background support.
   - Rename user-facing "Safari extensions" to Chrome MV3/browser extensions.
   - Keep disabled-runtime tests passing.

2. Install foundation
   - Add MV3 manifest validator/normalizer, original bundle store, generated bundle writer, and compatibility reporter.
   - Add fixture-based tests before loading any real runtime.

3. Runtime host skeleton
   - Introduce profile host, eligibility gate, capability registry, and controller/context lifecycle with no broad API support.
   - Prove disabled state and normal-tab-only attachment.

4. Password-manager MVP
   - Add runtime messaging, content script injection matrix, action popup, storage subset, activeTab, host permissions, and native messaging.
   - Run password-manager fixture acceptance tests.

5. Broader API expansion
   - Add context menus, alarms, webNavigation, downloads, notifications, sidePanel/offscreen/identity only when each has a spec and fixtures.

## Safari-Extension Deletion Plan

- Remove `.app` and `.appex` discovery from `ExtensionManager+Installation.swift`.
- Remove Safari extension install commands and settings copy from `App/SumiCommands.swift`, `SettingsView.swift`, and `SettingsUtils.swift`.
- Replace `SafariExtensionSourceKind`, `SafariExtensionBackgroundModel`, and `SafariExtensionTrustSummary` in `ExtensionModels.swift` with Chrome MV3 install/generation records.
- Remove MV2 `backgroundPage` and `eventPage` paths from `ExtensionUtils.swift` and `ExtensionManager+ManifestPatching.swift`.
- Delete `SafariNativeMessageRouter` and replace with explicit Chrome native messaging handling.
- Rename `safariWebExtension` toolbar slot identifiers only if no persisted compatibility is required; because Sumi is unpublished, clean rename/delete is preferred.
- Audit `webkit-extension` and `x-safari-https` handling in `Vendor/DDG/URLPredictor`; delete Sumi-specific dependency on Safari schemes unless another feature requires it.
- Keep WebKit adapter concepts that are required by `WKWebExtensionController`, `WKWebExtensionContext`, `WKWebExtensionTab`, and `WKWebExtensionWindow`.

## Test Strategy

- Keep and expand disabled-runtime tests in `SumiTests/BrowserConfigurationNormalTabTests.swift` and `SumiTests/SumiPerformanceModularRegressionTests.swift`.
- Add manifest validator tests for MV3 accepted, MV2 rejected, Safari `.appex` rejected, invalid paths rejected, unsupported APIs reported.
- Add generated-bundle golden tests for service-worker wrapper, JS shim, native bridge script, and manifest rewrite.
- Add web view eligibility tests for normal tabs, previews, mini windows, favicon helpers, options pages, and launcher metadata.
- Add password-manager fixture tests described above.
- Add service-worker lifecycle tests with fake clocks for wake reason, idle unload, hard timeout, bridge timeout, alarm wake, native port close, and extension disable.
- Add native messaging tests with fake host manifests and fake host processes.
- Add compatibility reporter tests for unsupported/deferred APIs.

## Spec-Kit / Specify Recommendation

Repository search found no `.specify`, spec-kit, or specify files. Do not install external tools for this task.

This Markdown document should be the planning/spec source for subsequent Codex tasks. If the repo later adopts spec-kit/specify, this document can be imported as the initial extension runtime specification.

## Risks and Open Questions

- WebKit's exact MV3 service-worker wake/unload behavior must be fixture-tested against system WebKit.
- WebKit's support for Chrome-compatible `storage.session`, dynamic `scripting`, `activeTab`, and frame injection semantics is not proven.
- `cookies`, `declarativeNetRequest`, `webRequest`, `offscreen`, `sidePanel`, `identity`, `downloads`, `bookmarks`, and `history` need separate API-specific specs before support.
- Native messaging host manifest lookup, user consent, sandboxing, process lifetime, and concurrency need a security review.
- Preview/Glance tabs currently use normal `Tab` infrastructure, so future eligibility logic must distinguish product surface from factory path.
- Existing `@unchecked Sendable` in native messaging should be treated as technical debt, not copied.
- Deleting vendor URL scheme handling may affect URL prediction tests; verify the dependency before editing vendor code.

## Proposed Prompt 02

Delete the unpublished Safari-extension product layer and MV2 support while keeping Sumi's extension module gate and disabled-runtime invariants intact. Scope the change to Safari `.app`/`.appex` discovery/install UI, Safari-named settings/commands/models, MV2 background model acceptance, and Safari-only native message routing. Do not add the Chrome MV3 runtime yet. Update or add tests proving that with extensions disabled there is no `WKWebExtensionController`, no contexts, no extension JS injection, no service-worker wakeups, and no native messaging runtime.
