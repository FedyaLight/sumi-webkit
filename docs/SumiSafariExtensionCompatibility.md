# Sumi Safari Web Extension Compatibility

Last updated: 2026-06-11 (Cycle 13 native WebKit cleanup: runtime.connect wrapper and stale externally-connectable bridge deleted)

Sumi targets native Safari Web Extension support through public WebKit APIs
(`WKWebExtension`, `WKWebExtensionContext`, `WKWebExtensionController`,
`WKWebExtensionControllerDelegate`). Chrome MV3 shims, CRX install paths, and
controlled Chrome compatibility popups are out of scope and must not return.

Deployment target remains **macOS 15.7** until a specific API is confirmed to
require macOS 27. Local SDK (Xcode macOS SDK) exposes `WKWebExtension` from
**macOS 15.4+** including `extensionWithAppExtensionBundle:completionHandler:`.

## Cycle 13 Stabilization Audit (2026-06-11)

Evidence base:

- Local SDK headers: `/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/WebKit.framework/Headers`
  confirm `WKWebExtension(appExtensionBundle:)`, `manifestVersion`,
  `WKWebExtensionController.Configuration.configurationWithIdentifier`,
  `defaultWebsiteDataStore`, `WKWebExtensionControllerDelegate`
  `sendMessage` / `connectUsing`, `WKWebExtension.MessagePort`, and
  `WKWebExtensionPermissionNativeMessaging`.
- Official Apple surfaces used as the contract:
  [`WKWebExtension`](https://developer.apple.com/documentation/webkit/wkwebextension),
  [`WKWebExtensionControllerDelegate`](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate),
  [action popup presentation](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller%28_%3Apresentactionpopup%3Afor%3Acompletionhandler%3A%29),
  [`WKWebExtensionContext.webViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration),
  [Safari web extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions),
  [Safari native app messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension),
  and [Safari optimization / MV3 guidance](https://developer.apple.com/documentation/safariservices/optimizing-your-web-extension-for-safari).
- Public architecture references only:
  [Bitwarden browser native-messaging `desktop_proxy` documentation](https://contributing.bitwarden.com/getting-started/clients/browser/biometric/)
  and [DuckDuckGo `apple-browsers`](https://github.com/duckduckgo/apple-browsers);
  no code copied and no product-specific runtime branch added.

### Already Correct

- Safari import stays native: `.app` / `.appex` discovery is read-only and runtime
  load prefers `WKWebExtension(appExtensionBundle:)`; persisted copied resources
  remain fallback-only and manifests are not patched.
- MV2 and MV3 remain separated by validation/background-model policy. Safari
  imports may load MV2 through WebKit while unpacked directory imports keep the
  stricter modern policy.
- Profile isolation is native WebKit: each Sumi profile owns a distinct
  `WKWebExtensionController`, `WKWebExtensionContext`, context identity, and
  `WKWebsiteDataStore`.
- Action popup, options page, extension-created tab/window, and normal-tab
  lifecycle continue through `WKWebExtensionControllerDelegate`; private tabs are
  blocked from popup/runtime eligibility.
- Native messaging uses WebKit delegate entry points and
  `WKWebExtension.MessagePort`; Sumi diagnostics log buckets and identifiers, not
  credentials, cookies, form values, tokens, or native-message payload bodies.
- Content scripts, CSS, and web-accessible resources are manifest/WebKit driven.
  The local inline-overlay fixture proves content-script `runtime.connect` to
  background `runtime.onConnect` and extension-page iframe resize without a Sumi
  `runtime.connect` wrapper.

### Fixed

- Removed the bounded timer retry in `SafariExtensionURLSchemeCompatibility` and
  replaced it with generic `browser` / `chrome` namespace assignment hooks. This
  preserves Safari-style `safari-web-extension:` public URLs while avoiding a
  user-script hot-path timer.
- Updated the inline overlay runtime fixture to assert
  `"runtimeConnectWrapped":false` on the successful resize path.
- Updated auxiliary-surface and modular-performance guards so they no longer keep
  stale externally-connectable handler names as expected filter inputs.

### Deleted

- `SafariExtensionRuntimeConnectCompatibility.swift`, including the private-SPI
  JavaScript `runtime.connect` / `runtime.onConnect` wrapper.
- Dormant externally-connectable bridge code:
  `ExtensionManager+ExternallyConnectableBridgeProtocol.swift`,
  `ExtensionManager+ExternallyConnectableLifecycle.swift`,
  `ExtensionManager+ExternallyConnectableModels.swift`,
  `ExtensionManager+ExternallyConnectableNativeMessaging.swift`,
  `ExtensionManagerSupport+BrokerSubfeatures.swift`, and
  `ExternallyConnectablePortRegistry.swift`.
- No-op install, teardown, state, and diagnostic references for the deleted bridge,
  including `sumiExternallyConnectableRuntime`, `SUMI_EC_PAGE_BRIDGE`, and the
  stale userscript hot-path exception.

### Tests Corrected

- `SafariExtensionCleanImportSourceGuardTests` now guards absence of the deleted
  runtime-connect wrapper and externally-connectable bridge artifacts.
- `SafariExtensionInlineOverlayRuntimeTests` now proves native WebKit
  `runtime.connect` / `runtime.onConnect` behavior instead of checking for a Sumi
  wrapper marker.
- `BrowserConfigurationNormalTabTests` and `SumiPerformanceModularRegressionTests`
  no longer model deleted bridge markers as auxiliary-filter inputs.
- `scripts/check_userscript_hot_paths.sh` no longer carries an exception for the
  deleted externally-connectable native-messaging file.

### Suspicious Code Intentionally Kept

- `SafariExtensionURLSchemeCompatibility` stays because Sumi uses WebKit's
  internal `webkit-extension:` base URL while Safari Web Extension code expects
  `safari-web-extension:` URLs at API and resource boundaries. The layer is
  generic, source-guarded, and not a Chrome MV3 shim.
- `SafariExtensionPermissionsOriginsCompatibility` stays because WebKit behavior
  around extension-origin permission checks with explicit ports is still covered
  by generic tests. It is scoped to extension worlds and does not patch
  manifests.
- `BitwardenNativeMessagingAdapter` stays as a native messaging protocol adapter,
  not generic runtime branching. Generic relay code remains source-guarded
  against Bitwarden-specific branches except adapter registration/resolution.

### Proven Remaining Gaps

- Raindrop, Bitwarden, 1Password, and Proton Pass manual E2E checks were not
  re-run in this audit. Automated tests preserve the covered behavior, but the
  final product claims still require the manual checklist below.
- 1Password and Proton Pass desktop IPC remains adapter-unavailable /
  protocol-unknown by design until a documented generic adapter exists.
- Safari/WebKit docs do not expose a Chrome-style host-manifest IPC surface.
  Native messaging remains routed through Sumi's WebKit delegate implementation.

## Phase 0 Code Audit (2026-06-10)

### Generic anchors to preserve

| Area | Location | Notes |
|------|----------|-------|
| Optional module gate | `SumiExtensionsModule` | Module off tears down controller/context; no background work |
| Runtime coordinator | `ExtensionManager` | WKWebExtension controller, contexts, lifecycle |
| Tab/window bridge | `ExtensionBridge.swift` | `WKWebExtensionTab` / `WKWebExtensionWindow` adapters |
| Delegate / UI surfaces | `ExtensionManager+ControllerDelegate`, `+UI` | Popups, permissions, options, action updates |
| Profile isolation | `ExtensionManager+ProfileRuntime`, `+Profiles` | Per-profile `WKWebExtensionController`, contexts, data stores |
| Persistence | `ExtensionModels.swift`, `+Store` | `ExtensionEntity`, installed records |
| URL-hub action surface | `BrowserExtensionSurfaceStore`, `ExtensionActionView` | Icons, badges, popup requests |
| Settings UI | `SumiExtensionsSettingsPane` | Enable/disable, uninstall |

### Chrome MV3 remnants (removed — do not restore)

| Area | Location | Status |
|------|----------|--------|
| Manifest disk patching | `ExtensionManager+ManifestPatching` (historical) | **Removed in Cycle 11** — no `patchManifestForWebKit`, no `sumi_webkit_runtime_compat*` writes |
| Compat JS bundle | `ExtensionRuntimeResources/*.js` | **Deleted in Cycle 11** — `webkit_runtime_compat*`, `externally_connectable_*`, `selective_content_script_guard` |
| Page-world EC bridge injection | `SumiExternallyConnectableUserScript` | **Removed in Cycle 11** — normal tabs no longer inject compat bridge scripts |
| Externally-connectable native relay (legacy) | `ExtensionManager+ExternallyConnectableNativeMessaging` | **Deleted in Cycle 13** — no active registration or runtime dependency |
| Architecture doc wording | `docs/architecture.md` | Still says "Chrome MV3" — update in cleanup phase |
| Stale test guards | `SumiPerformanceModularRegressionTests`, `NativeMessagingProcessSessionTests` | Assert old `ChromeMV3*` symbols absent (good) |

No production `ChromeMV3NativeMessagingInternalRuntime` or CRX installer found.

### Clean vs patched Safari import (Cycle 11)

| Stage | Behavior |
|-------|----------|
| Scanner | Read-only `.app` → `PlugIns/*.appex` discovery (`SafariExtensionScanner`) |
| Import copy | Flat resource copy for persistence only (`SafariAppExtensionResources.copyResources`) — **manifest untouched** |
| Runtime load | **Prefers signed on-disk `.appex`** via `WKWebExtension(appExtensionBundle:)`; falls back to copied package via `WKWebExtension(resourceBaseURL:)` |
| Manifest | **Never rewritten** on install or enable |
| Compat JS | **Not copied, generated, or injected** |
| Popup / action | WebKit-managed `WKWebExtension.Action` surfaces only |
| Content scripts | WebKit manifest-driven injection only |
| Native messaging | Swift `SumiNativeMessagingRelay` + `WKWebExtensionControllerDelegate` — not JS-shimmed |
| Unsupported APIs | Documented as blocked in compatibility report — **not faked via JS** |

Source guards: `SafariExtensionCleanImportSourceGuardTests`, `scripts/check_safari_extension_clean_import.sh`.

### Reusable UI surfaces

- `ExtensionActionView` — toolbar / URL-hub action button host
- `SumiExtensionsSettingsPane` — extension list and toggles
- Permission / popup hosting in `ExtensionManager+ControllerDelegate` and `+UI`

### Safari-native candidates (existing)

| Component | WebKit API | Sumi status |
|-----------|------------|-------------|
| Extension load (directory) | `WKWebExtension(resourceBaseURL:)` | Implemented |
| Extension load (appex) | `WKWebExtension(appExtensionBundle:)` | **Wired (Cycle 5)** — validate on import; runtime prefers original `.appex` when still installed, else copied package |
| Context + controller | `WKWebExtensionContext`, `WKWebExtensionController` | Implemented |
| Delegate | `WKWebExtensionControllerDelegate` | Implemented |
| Tab/window model | `WKWebExtensionTab`, `WKWebExtensionWindow` | Implemented via adapters |
| Action / popup | `WKWebExtension.Action`, `presentActionPopup` | Implemented |
| Permissions | `WKWebExtension.Permission`, match patterns | Partial (grant on install; delegate prompts exist) |
| Messaging | `WKWebExtension.MessagePort`, `connectUsing` | **Sumi relay wired (Cycle 8)** — policy + resolver + port session; companion protocol unknown |
| Post-enable runtime finalize | Background wake + action surface seed | **Added (Cycle 3)** |
| Dev compatibility report | `SafariExtensionCompatibilityReport` | **Extended (Cycle 6)** — platform blockers + acceptance matrix |
| Acceptance harness | `SafariExtensionAcceptanceMatrix` | **Added (Cycle 6)** — DEBUG/test automated checks |
| Module off = zero runtime | `SumiExtensionsModule.tearDownLoadedRuntime` | Implemented |

### Cycle 1 addition

| Component | Status |
|-----------|--------|
| `SafariExtensionScanner` | **Added** — discovers `.appex` inside `.app` without loading WebKit runtime |

### Cycle 3 addition

| Component | Status |
|-----------|--------|
| `finalizeEnabledExtensionRuntime` | **Added** — background wake + URL-hub action seed after enable/load |
| `SafariExtensionCompatibilityReport` | **Added** — dev diagnostics (`RuntimeDiagnostics` verbose) |
| `SafariExtensionCompatibilityTargets` | **Added** — PM target bundle ID constants + probe test |

### Cycle 6 addition

| Component | Status |
|-----------|--------|
| `SafariExtensionAcceptanceMatrix` | **Added** — automated checks (scanner, import source, synthetic enable action surface, tab reconcile, Raindrop tab adapter) |
| `SafariExtensionPlatformBlocker` | **Cycle 8** — `hostApplicationMessageRelay` removed; use classification buckets |
| `SafariExtensionHostRelayAPIProbe` | **Added** — macOS 27.0 SDK header scan; `#available(macOS 27, *)` probe returns `false` |
| Compatibility report | **Extended** — per-entry + global `platformBlockers`, `sdkProbeNote` |
| `ExtensionTabAdapter.shouldBypassPermissions` | **Added** — returns `false` (enforce host permission checks for tabs API / save flow) |
| Content-script probe | **Added** — verifies `reconcileOpenTabsAfterExtensionContextLoad` wiring in enable path |
| Manual autofill fixture | **Documented** — see Acceptance manual steps below |

### Cycle 10 addition

| Component | Status |
|-----------|--------|
| Per-profile extension runtime | **Fixed** — `WKWebExtensionController` + `WKWebExtensionContext` + `WKWebsiteDataStore` per Sumi profile |
| Profile-scoped context identity | **Added** — scoped `uniqueIdentifier` / `baseURL` prevent cross-profile context collision |
| Tab/window bridge filtering | **Updated** — adapters expose only same-profile tabs/windows |
| Native messaging relay scope | **Updated** — ports associated with `(profileID, extensionID)` |
| Private tab popup guard | **Preserved** — ephemeral tabs remain ineligible for action popups |
| Tests | **Added** — `SafariExtensionProfileIsolationTests` |

### Cycle 9 addition

| Component | Status |
|-----------|--------|
| `SafariExtensionSessionDiagnostics` | **Added** — sanitized popup/tab store alignment + cookie domain counts (no values) |
| Extension runtime data-store alignment | **Fixed** — extension controller/page/popup configs share active profile `WKWebsiteDataStore` |
| Import auto-enable | **Added** — explicit Safari import calls `enableExtension` after persist; failures leave extension disabled + `importSucceededEnableFailed` |
| Settings UI | **Updated** — installed extensions above import candidates; toggle + trash controls |
| Navigation completion | **Improved** — `navigationDidFinish` emits tab URL/title/loading updates to WebKit |

### Cycle 8 addition

| Component | Status |
|-----------|--------|
| `SumiNativeMessagingRelay` | **Added** — Sumi-owned delegate relay (send + connect) |
| `SumiNativeMessagingRelayPolicy` | **Added** — module/enabled/Safari-import/private-browsing gates |
| `SumiNativeMessagingAppResolver` | **Added** — containing app → alias → metadata resolver buckets |
| `SumiNativeMessagingConnection` | **Added** — one-shot send with timeout/cancellation |
| `SumiNativeMessagingPortSession` | **Added** — persistent `WKWebExtension.MessagePort` wiring |
| `SafariExtensionNativeMessagingClassification` | **Added** — precise readiness buckets (no false platform blockers) |
| `SafariExtensionNativeMessagingProbeBuilder` | **Added** — sanitized DEBUG probe report |
| DEBUG menu command | **Added** — Extensions → Run Safari Extension Native Messaging Probe |
| `hostApplicationMessageRelay` platform blocker | **Removed** — reclassified as `companionAppProtocolUnknown` |

### Cycle 7 addition

| Component | Status |
|-----------|--------|
| `testLiveAcceptanceMatrixAgainstInstalledTargets` | **Added** — real `/Applications` scan; scanner + import + tab reconcile |
| DEBUG menu command | **Added** — Extensions → Run Safari Extension Acceptance Check |
| `SafariExtensionManualE2ETests` | **Added** — skipped-by-default per-target manual checklist |
| Popup presentation fixes | **Added** — minimum popover size, non-zero anchor rect, autoresizing anchor |
| `grantActiveTabURLAccess` | **Added** — activeTab URL grant on URL-hub action + `presentActionPopup` |

### Cycle 5 addition

| Component | Status |
|-----------|--------|
| `SafariAppExtensionResources.makeWebExtension` | **Added** — prefers `WKWebExtension(appExtensionBundle:)` from `sourceBundlePath` when `.appex` still on disk |
| `SafariAppExtensionRuntimeLoadSource` | **Added** — `originalAppexBundle` vs `copiedPackage` metadata for diagnostics |
| `reconcileOpenTabsAfterExtensionContextLoad` | **Added** — enable/load path re-binds tabs + late-assigns controller for content scripts |
| `SafariExtensionPopupLoadStatus` | **Added** — compatibility report bucket: `notApplicable` / `unavailable` / `empty` / `loaded` / `error` |
| Original appex NM probe | **Investigated** — loading from signed `.appex` does not expose public host relay; `hostRelayUnavailable` remains |

### Cycle 4 addition

| Component | Status |
|-----------|--------|
| `SafariExtensionNativeMessagingHost` | **Added** — public WebKit delegate bridge; host bundle resolve + `NSWorkspace` wake |
| `SafariExtensionNativeMessagingResolver` | **Added** — maps extension context / `applicationIdentifier` → host `.app` bundle ID |
| `NativeMessagingHandler` | **Extended** — retains `WKWebExtension.MessagePort`, sanitized port diagnostics |
| Delegate wiring | **Wired** — `sendMessage` / `connectUsing` in `ExtensionManager+ControllerDelegate` |

### Cycle 2 addition

| Component | Status |
|-----------|--------|
| `WebExtensionSourceKind.safariAppExtension` | **Added** |
| `resolveInstallSource` | **Extended** — direct `.appex`, single-extension `.app` |
| `performInstallation` appex path | **Added** — `WKWebExtension(appExtensionBundle:)` validation, copy for persistence, `enableOnInstall` gate |
| `SafariExtensionImportStore` | **Added** — discovered vs imported registry (no auto-enable) |
| `SafariExtensionImportCandidatesSection` | **Added** — settings UI with explicit Import |

## API Compatibility Matrix

| API / capability | Apple availability | Local SDK | Sumi status | Tests | Target extensions |
|------------------|-------------------|-----------|-------------|-------|-------------------|
| `WKWebExtension` (resource base URL) | macOS 15.4+ | Yes | Implemented | Install/runtime tests | All |
| `WKWebExtension` (app extension bundle) | macOS 15.4+ | Yes | **Runtime prefers original `.appex` (Cycle 5)** | `SafariExtensionInstallSourceTests` | All |
| `WKWebExtensionController` | macOS 15.4+ | Yes | Implemented | Modular regression | All |
| `WKWebExtensionControllerDelegate` | macOS 15.4+ | Yes | Implemented | Partial | All |
| Tab/window adapters | macOS 15.4+ | Yes | Implemented | — | Raindrop, PMs |
| Action icon / popup | macOS 15.4+ | Yes | Implemented | `ExtensionActionVisibilityTests` | All |
| Permission delegate | macOS 15.4+ | Yes | Partial | — | All |
| `runtime.sendMessage` / `connect` | WebKit extension runtime | Yes | Unverified on targets | — | Bitwarden, 1Password, Proton |
| Native app messaging (Safari / WebKit delegate) | `sendMessage` / `connectUsing` | macOS 15.4+ | **Implemented — Sumi relay resolves host, wakes via `NSWorkspace`, returns `companionAppProtocolUnknown` until companion IPC is documented** | `SumiNativeMessagingRelayTests`, `SafariExtensionNativeMessagingHostTests` | Bitwarden, 1Password, Proton |
| Externally-connectable page bridge NM | Custom JS shim | N/A | **Removed (Cycle 11)** | `SafariExtensionCleanImportSourceGuardTests` | N/A |
| Content scripts / autofill | WebKit | Yes | **Enable path tab reconcile (Cycle 5)** | `SafariExtensionCompatibilityReportTests` | All PMs |
| `storage.local` / `storage.sync` | WebKit | Yes | Assumed via WebKit stores | Store lifecycle traces | PMs |
| System Safari extension discovery | N/A (filesystem) | N/A | **Scanner added (Cycle 1)** | `SafariExtensionScannerTests` | All |
| Import installed `.appex` | `WKWebExtension(appExtensionBundle:)` | Yes | **Implemented (import auto-enables; disable on enable failure)** | `SafariExtensionInstallSourceTests`, `SafariExtensionImportAutoEnableTests` | All |

## Target Extension Acceptance Matrix

Cycle 6 adds `SafariExtensionAcceptanceMatrix` (DEBUG / `SafariExtensionAcceptanceMatrixTests`)
for automated checks. Manual E2E (import + enable + popup + save/autofill) still required.

### Automated checks (Cycle 6)

| Check | What it verifies |
|-------|------------------|
| `scannerFindsInstalledTarget` | PM/Raindrop `.appex` discovered when containing app is in search roots |
| `importSourceResolvable` | `SafariAppExtensionResources.installedAppexBundleURL` or manifest readable |
| `syntheticEnableActionSurfaceReady` | Enabled extension with `hasAction` has context/action after enable path |
| `contentScriptTabReconcileWired` | `reconcileOpenTabsAfterExtensionContextLoad` in finalize/enable path |
| `raindropTabAdapterPrerequisites` | `ExtensionTabAdapter` exposes url/title/webView/activeTab gesture + `shouldBypassPermissions == false` |
| `popupAnchorPresentationWired` | `ExtensionManager+ActionPopupAnchor` capture/resolve/present path |
| `nativeMessagingSuppressionReportWired` | Loop guard + diagnostic coalescer + `sessionState` on NM diagnostics |
| `passwordManagerLocalFormFixtureAvailable` | `SumiTests/Fixtures/Extensions/login-form.html` present for PM autofill manual probe |

Invoke in DEBUG: `SumiExtensionsModule.shared.safariExtensionAcceptanceMatrix()` or **Run Safari Extension Dev Diagnostics Report** (verbose JSON via `RuntimeDiagnostics` when enabled).

### Manual acceptance steps (per target)

1. **Settings → Extensions → Safari imports** — import the target `.appex` (Sumi enables immediately when runtime load succeeds).
2. Confirm URL-hub action icon appears on `https://` page (toggle off/on in Installed Extensions if needed).
3. **Popup** — click action; confirm non-empty popup (`popupLoadStatus` → `loaded` in compatibility report).
4. **Content scripts / autofill (PMs only)** — open a page with a login form; confirm field icons or autofill prompt.
   Manual fixture: any `https://` login page (e.g. `https://example.com` HTML form with `input type=password`) or a local `login-form-fixture.html` with username/password fields.
5. **Native messaging (PMs only)** — unlock attempt should wake host app; relay returns `companionAppProtocolUnknown` (not a platform blocker).
6. **Raindrop save** — on `https://` article, click Raindrop action; confirm save UI without host-app relay.

### Acceptance status table (automated + manual)

### Real bundle IDs (Cycle 3 dev-machine probe, read-only)

| Target | Containing app | App bundle ID | Safari `.appex` bundle ID |
|--------|----------------|---------------|---------------------------|
| Bitwarden | `Bitwarden.app` | `com.bitwarden.desktop` | `com.bitwarden.desktop.safari` |
| 1Password | `1Password for Safari.app` | `com.1password.safari` | `com.1password.safari.extension` |
| Proton Pass | `Proton Pass for Safari.app` | `me.proton.pass.catalyst` | `me.proton.pass.catalyst.safari-extension` |
| Raindrop | `Save to Raindrop.io.app` | `io.raindrop.safari` | `io.raindrop.safari.extension` |

All four containing apps were present under `/Applications` on the Cycle 3 dev machine.
Raindrop also ships a non-web-extension `Share.appex` (`io.raindrop.safari.Share`) which the
scanner correctly classifies as non-Safari extension point.

| Check | Bitwarden | 1Password | Proton Pass | Raindrop |
|-------|-----------|-----------|-------------|----------|
| Scanner (automated) | **Pass** (Cycle 7 live) | **Pass** | **Pass** | **Pass** |
| Import source (automated) | **Pass** | **Pass** | **Pass** | **Pass** |
| Tab reconcile wired (automated) | Pass | Pass | Pass | Pass |
| Tab adapter prerequisites (automated) | — | — | — | Pass |
| Popup anchor probe (automated) | Pass | Pass | Pass | Pass |
| NM suppression report (automated) | Pass | Pass | Pass | Pass |
| PM local form fixture (automated) | Pass | Pass | Pass | N/A |
| NM classification `noChromeStyleNativeHostRelay` | Yes | Yes | Yes | Yes |
| NM classification `wkWebExtensionAppMessagingAvailable` | Yes | Yes | Yes | Yes |
| NM classification `companionAppProtocolUnknown` | Yes | Yes | Yes | — |
| Platform blocker | None | None | None | None |
| Import + enable (manual) | **Yes** | Not verified | Not verified | **Yes** |
| MV2 manifest warning observed (manual) | **Yes** | Not verified | Not verified | N/A |
| URL-hub icon + popup (manual) | **Yes** | Not verified | Not verified | **Yes** |
| Sign-in session in popup (manual) | **Yes** | Not verified | Not verified | **Yes** |
| Profile isolation (manual) | Pending | Not verified | Not verified | **Yes** |
| Desktop launch loop (manual) | **No** (suppressed) | Not verified | Not verified | N/A |
| Native messaging protocol (manual) | **Unknown** (`companionAppProtocolUnknown`) | **Unknown** | **Unknown** | N/A |
| Content script / autofill (manual) | **Classified** (pending retest) | Not verified | Not verified | N/A |
| Popup anchoring (manual) | **Fixed** | Not verified | Not verified | **Yes** |
| Save bookmark flow (manual) | N/A | N/A | N/A | **Yes** |

Cycle 7 live probe (dev machine, all four containing apps in `/Applications`):
`testLiveAcceptanceMatrixAgainstInstalledTargets` passed scanner + import + tab reconcile for every installed target.

### Manual E2E checklist (not runnable in CI)

Run with Extensions module enabled. Use DEBUG → Extensions → **Run Safari Extension Acceptance Check**, **Run Safari Extension Native Messaging Probe**, or **Run Safari Extension Dev Diagnostics Report** for automated JSON (acceptance matrix + runtime diagnostics + NM probe).

1. **Import** — Settings → Extensions → Safari imports → Import target (do not enable yet).
2. **Enable** — Toggle on in extension list; confirm URL-hub action icon on any `https://` page.
3. **Popup** — Click action; popup must be non-empty (not zero-size / blank).
4. **PM autofill** (Bitwarden, 1Password, Proton only) — open a page with `input type=password`; confirm field icons or autofill UI.
5. **PM native unlock** — host app may wake via `NSWorkspace`; JSON relay returns `companionAppProtocolUnknown` until companion IPC is known.
6. **Raindrop save** — on article `https://` page, action popup shows title/URL; save completes without host relay.

Skipped UI tests documenting these steps: `SumiUITests/SafariExtensionManualE2ETests.swift` (not in default test plan; run individually in Xcode).

## Native messaging readiness audit (Cycle 8)

Safari / WebKit native messaging is **not** the Chrome `externally_connectable` JS bridge or
Chrome `nativeMessaging` host manifests (`noChromeStyleNativeHostRelay`).

### Classification buckets (use precisely)

| Bucket | Meaning |
|--------|---------|
| `noChromeStyleNativeHostRelay` | Chrome MV3 subprocess/manifest relay is out of scope — not a platform blocker |
| `wkWebExtensionAppMessagingAvailable` | Public delegate `sendMessage` / `connectUsing` + `WKWebExtension.MessagePort` (macOS 15.4+) |
| `sumiRelayNotImplemented` | Sumi delegate wiring or policy missing |
| `companionAppProtocolUnknown` | Host `.app` JSON/XPC protocol not documented for Sumi relay |
| `platformBlocked` | Hard blocker with public-SDK proof only — **not used for native messaging in Cycle 8** |

### Public API evidence (macOS 15.4+, local SDK)

Verified in `MacOSX27.0.sdk` and Xcode `MacOSX26.5.sdk` (identical `WKWebExtension*.h`):

- `webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:)` — macOS 15.4+
- `webExtensionController(_:connectUsing:for:completionHandler:)` — macOS 15.4+ (ObjC: `connectUsingMessagePort:`)
- `WKWebExtension.MessagePort` — `applicationIdentifier`, `messageHandler`, `sendMessage`, `disconnect`
- `WKWebExtensionPermissionNativeMessaging` — macOS 15.4+

**Absent from public SDK:** Chrome-style `NativeMessagingHosts` manifests, browser→third-party-host
IPC primitives (no documented XPC service for arbitrary companion apps). The delegate places
**Sumi** in the relay path — that is the intended integration surface (`wkWebExtensionAppMessagingAvailable`).

### Sumi relay implementation (Cycle 8)

| Component | Role |
|-----------|------|
| `SumiNativeMessagingRelay` | Delegate entry: send + connect |
| `SumiNativeMessagingRelayPolicy` | Extensions module, enabled Safari import, private-browsing gate |
| `SumiNativeMessagingAppResolver` | Containing app → alias table → metadata → no-match |
| `SumiNativeMessagingConnection` | One-shot send, `NSWorkspace` wake, timeout/cancellation |
| `SumiNativeMessagingPortSession` | Retains `WKWebExtension.MessagePort`, bidirectional wiring |
| `SafariExtensionNativeMessagingDiagnostics` | Sanitized probe + runtime diagnostics (no message bodies) |

| Path | Status |
|------|--------|
| `sendMessage(toApplicationWithIdentifier:…)` | Resolves host, wakes via `NSWorkspace`, returns `companionAppProtocolUnknown` (code 3) |
| `connectUsing(_:for:…)` | Wakes host, completes port; first extension message → `companionAppProtocolUnknown` disconnect |
| Host bundle resolution | Alias table: `com.8bit.bitwarden` → `com.bitwarden.desktop`, `me.proton.pass.nm` → `me.proton.pass.catalyst` |
| Externally-connectable bridge | Deleted; native messaging enters only through WebKit delegate send/connect callbacks |

**Reclassification:** `hostApplicationMessageRelay` was removed as a `platformBlocked` entry in
Cycle 8. Absence of Chrome-style relay is expected on Safari. PM unlock pending
`companionAppProtocolUnknown` — not `platformBlocked`.

### macOS 27.0 / WebKit SDK probe (Cycle 8 re-verify)

Probe machine: **macOS 27.0** (`MacOSX27.0.sdk` at
`/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk`).

| Probe | Result |
|-------|--------|
| `API_AVAILABLE(macos(26\|27))` NM additions in `WKWebExtension*.h` | **None** |
| Delegate `sendMessage` / `connectUsing` | **Present** macOS 15.4+ |
| Chrome-style host manifest APIs | **Absent** (expected) |
| `SafariExtensionHostRelayAPIProbe.wkWebExtensionAppMessagingAvailable` | `true` |

Sumi deployment target remains **macOS 15.7**.

## Profile isolation (Cycle 10)

Manual repro: Profile A login visible in Profile B popup mapped to
**`extensionControllerSharedAcrossProfiles` + `extensionContextSharedAcrossProfiles`**:
a single global `WKWebExtensionController` and shared `WKWebExtensionContext` instances were
reused across profiles; `switchProfile` only swapped `defaultWebsiteDataStore` on the shared
controller (insufficient — background/service-worker state and extension storage remained shared).

Generic fix (public WebKit APIs only):

- One persistent `WKWebsiteDataStore(forIdentifier: profileId)` per Sumi profile (unchanged).
- One `WKWebExtensionController.Configuration(identifier:)` per profile (distinct from profile store ID).
- One loaded `WKWebExtensionContext` per `(profileId, extensionId)` with profile-scoped identity.
- Tab WebViews late-bind the controller for their tab's profile.
- Action popup resolves profile from active tab before loading context.
- Native messaging ports record owning profile ID.

| Bucket | Cycle 10 result |
|--------|-----------------|
| `extensionControllerSharedAcrossProfiles` | **Root cause — fixed** |
| `extensionContextSharedAcrossProfiles` | **Root cause — fixed** |
| `extensionDataStoreUsesLastActiveProfile` | **Removed** (no shared-controller store swap) |
| `cookieStoreNotShared` | **Remains fixed** from Cycle 9 |
| Private tabs blocked | **Preserved** |

### SDK notes (macOS 27.0, verified locally)

- `WKWebExtensionController.Configuration.configurationWithIdentifier:` — persistent unique storage per controller; SDK requires unique configuration when using multiple controllers.
- `WKWebsiteDataStore.dataStoreForIdentifier:` — stable per-profile browsing data; `fetchAllDataStoreIdentifiers` lists persistent stores.
- `WKHTTPCookieStore` — per data store; no partitioned-cookie API additions found in macOS 27 SDK headers.
- Safari 27 / WebKit 27 Cookie Store `maxAge` — no native host API distinction found in public SDK; treat as web-platform surface unless WebKit documents otherwise.
- `WKWebExtensionController` — multiple instances supported; bind to `WKWebViewConfiguration.webExtensionController` per profile runtime.

## Session/auth diagnostics (Cycle 9)

Raindrop manual repro (import → popup → sign-in tab → login → popup still unsigned-in) mapped to
**`cookieStoreNotShared`**: extension popup/background surfaces inherited
`WKWebsiteDataStore.default()` while normal login tabs used the active profile store.

Generic fix: `syncExtensionRuntimeWebsiteDataStore`, profile-backed
`makeExtensionPageBaseWebViewConfiguration`, and `prepareWebViewConfigurationForExtensionRuntime`
alignment. Sanitized diagnostics via `SafariExtensionSessionDiagnostics` (store identifiers,
cookie domain counts only, popup lifecycle phase).

| Bucket | Cycle 9 Raindrop result |
|--------|-------------------------|
| `cookieStoreNotShared` | **Root cause — fixed generically** |
| `navigationEventNotDelivered` | Mitigated (`navigationDidFinish` tab property updates) |
| `popupContextReset` | Observed on transient popover close; reopen expected |
| `companionAppProtocolUnknown` | N/A for Raindrop |

## Known gaps / next work

1. **End-to-end manual validation** on Bitwarden / 1Password / Proton Pass after
   import + enable (popup, content scripts, native messaging wake). Raindrop login/session
   fixed generically in Cycle 9 — retest save flow.
2. **Companion app protocol** — document/reverse-engineer PM host `.app` JSON relay
   (`companionAppProtocolUnknown`); no Chrome manifest relay.
3. **Manifest patching vs appex runtime** — copied package remains patched for fallback; appex
   runtime reads unpatched signed manifest (acceptable for NM probe; compat JS only on fallback).
4. Reduce manifest patching surface where WebKit 27 makes compat JS unnecessary.

## Engineering cycles log

### Cycle 1 (2026-06-10)

- Phase 0 audit documented (this file).
- Added `SafariExtensionScanner` with safe `.app` → `Contents/PlugIns/*.appex` discovery.
- Added unit tests with synthetic bundle fixtures and negative cases.
- **Blocker for Cycle 2:** connect scanner output to import flow via
  `WKWebExtension(appExtensionBundle:)`.

### Cycle 2 (2026-06-10)

- Added `WebExtensionSourceKind.safariAppExtension`.
- Extended `resolveInstallSource` for `.appex` and single-extension `.app` bundles.
- `performInstallation` validates appex via `WKWebExtension(appExtensionBundle:)`, copies
  resources into Sumi's managed store (persistence across host-app updates / manifest patch),
  and loads runtime only when `enableOnInstall` is true (settings import uses `false`).
- Added `SafariExtensionImportStore` and settings import UI (`SafariExtensionImportCandidatesSection`).
- Fixed `enableExtension` to `loadEnabledExtension` when context is missing after disabled import.
- Tests: `SafariExtensionInstallSourceTests`, `SafariExtensionImportStoreTests` (all pass with scanner tests).
- **Blocker for Cycle 3:** manual E2E on target password managers / Raindrop after import + enable.

### Cycle 3 (2026-06-10)

- **Post-enable runtime finalize:** `finalizeEnabledExtensionRuntime` wakes background worker and
  seeds URL-hub action surface after `loadEnabledExtension` / `enableExtension` (fixes disabled-import
  → enable path where popup/background stayed cold).
- **`SafariExtensionCompatibilityReport`:** per-target sanitized status (discovered, imported,
  context, action, error bucket); logs JSON only when `RuntimeDiagnostics.isVerboseEnabled`.
- **Real bundle probe:** all four PM targets found in `/Applications`; bundle IDs recorded above.
  `SafariExtensionCompatibilityReportTests.testRealBundleProbeRecordsExpectedIdentifiersWhenPresent`
  asserts scanner output when apps are installed.
- **Native messaging audit:** documented WebKit delegate stubs vs externally-connectable bridge (above).
- Tests: `SafariExtensionCompatibilityReportTests` added; existing Safari extension test suites pass.
- **Blocker for Cycle 4:** manual PM testing (import → enable → URL-hub popup) on dev machine;
  native messaging implementation for password managers.

### Cycle 4 (2026-06-10)

- **`SafariExtensionNativeMessagingHost`:** resolves host `.app` bundle ID from
  `applicationIdentifier` + Safari import metadata; wakes host via `NSWorkspace.openApplication`.
- **`SafariExtensionNativeMessagingResolver`:** alias table for PM host IDs
  (`com.8bit.bitwarden` → `com.bitwarden.desktop`, `me.proton.pass.nm` → `me.proton.pass.catalyst`);
  empty identifier falls back to containing app from imported appex path.
- **Delegate wired:** `ExtensionManager+ControllerDelegate` `sendMessage` / `connectUsing` call host
  bridge; `NativeMessagingHandler` retains `WKWebExtension.MessagePort`.
- **Diagnostics:** sanitized buckets only (`extensionId`, direction, host bundle ID, outcome,
  error domain/code) — never message bodies.
- **Tests:** `SafariExtensionNativeMessagingHostTests`, updated `NativeMessagingProcessSessionTests`
  and modular regression guards.
- **Blocker for Cycle 5:** public host IPC relay for PM unlock/autofill; manual E2E after import.

### Cycle 5 (2026-06-10)

- **Original appex runtime load:** `SafariAppExtensionResources.makeWebExtension` prefers signed
  `.appex` at `sourceBundlePath` in `loadEnabledExtension` / `performInstallation` enable path.
- **Content scripts on enable:** `reconcileOpenTabsAfterExtensionContextLoad` called from
  `finalizeEnabledExtensionRuntime` (tab generation bump, controller late-bind, window resync).
- **Popup diagnostics:** `SafariExtensionPopupLoadStatus` + `safariRuntimeLoadSource` on compatibility entries.
- **NM probe finding:** original-bundle load does not change public relay behavior; platform blocker documented.
- Tests: extended `SafariExtensionInstallSourceTests`, `SafariExtensionCompatibilityReportTests`.
- **Blocker for Cycle 6:** public Sumi ↔ host `.app` message relay API; manual PM E2E (popup loaded bucket).

### Cycle 6 (2026-06-10)

- **`SafariExtensionAcceptanceMatrix`:** automated scanner/import/synthetic-enable/tab-reconcile/Raindrop tab checks.
- **`SafariExtensionPlatformBlocker`:** `hostApplicationMessageRelay` with header-cited evidence on compatibility + acceptance reports.
- **macOS 27.0 SDK probe:** no new public host-relay APIs; `#available(macOS 27, *)` probe returns `false`.
- **Raindrop tab adapter:** `shouldBypassPermissions` → `false`; probe validates url/title/webView/activeTab surface.
- **Tests:** `SafariExtensionAcceptanceMatrixTests` + extended compatibility report tests.
- **Blocker for Cycle 7:** manual E2E on all four targets; public host JSON relay API (monitor WebKit / Feedback).

### Cycle 7 (2026-06-10)

- **Build:** `xcodebuild build -scheme Sumi -destination 'platform=macOS'` — **BUILD SUCCEEDED**.
- **Live acceptance matrix:** `testLiveAcceptanceMatrixAgainstInstalledTargets` — all four targets in `/Applications`; scanner + import + tab reconcile **pass**.
- **Popup fixes:** minimum `NSPopover.contentSize`, non-zero anchor rect fallback, `ActionAnchorView` autoresizing mask.
- **Raindrop activeTab:** `grantActiveTabURLAccess` on URL-hub `performAction` and `presentActionPopup`.
- **DEBUG menu:** Extensions → Run Safari Extension Acceptance Check → stdout JSON when module enabled.
- **Manual E2E scaffold:** `SafariExtensionManualE2ETests` (4 `XCTSkip` tests; not in default scheme test plan).
- **Tests:** 39 Safari-extension unit tests pass across 6 `SumiTests` suites.
- **macOS 27.0 SDK re-probe (parallel):** `MacOSX27.0.sdk`; no new public host-relay APIs; blocker unchanged.
- **Blocker for Cycle 8:** manual import → enable → popup on all four targets; companion app IPC protocol.

### Cycle 9 (2026-06-10)

- **Raindrop auth/session gap:** diagnosed as `cookieStoreNotShared`; extension runtime page
  configuration now uses the active profile `WKWebsiteDataStore` (same as normal tabs).
- **`SafariExtensionSessionDiagnostics`:** popup open/close/reopen, store identifier alignment,
  cookie domain counts (no values), permission bucket summary.
- **Import auto-enable:** `importSafariAppExtension` persists then `enableExtension`; enable
  failure → disabled + `ExtensionError.importSucceededEnableFailed`.
- **Settings UI:** installed extensions listed above Safari import candidates; toggle + trash.
- **Tests:** `SafariExtensionRuntimeDataStoreTests`, `SafariExtensionImportAutoEnableTests`,
  `SafariExtensionSessionDiagnosticsTests`.

### Cycle 13 (2026-06-11)

- **Deleted runtime-connect wrapper:** `SafariExtensionRuntimeConnectCompatibility.swift`
  removed after `SafariExtensionInlineOverlayRuntimeTests` passed with native
  WebKit `runtime.connect` / `runtime.onConnect`.
- **Deleted stale externally-connectable bridge:** bridge protocol, lifecycle,
  models, native-messaging bridge, port registry, broker subfeature, no-op
  install/teardown state, docs, and hot-path exception removed.
- **URL-scheme compatibility narrowed:** retry timers replaced with namespace
  assignment hooks; `scripts/check_userscript_hot_paths.sh` passes.
- **Tests:** clean-import guard, inline-overlay runtime, auxiliary config,
  performance modular guards, and targeted Safari/WebKit extension suite pass.
- **Build:** `xcodebuild build -project Sumi.xcodeproj -scheme Sumi -configuration Debug -destination 'platform=macOS'`.

### Cycle 12 (2026-06-10)

- **`SafariExtensionRuntimeDiagnostics`:** sanitized scripting/content-script/host-permission/tab-frame/popup-anchor status per target.
- **`SafariExtensionManualVerificationCatalog`:** documented manual acceptance matrix (Raindrop verified; Bitwarden partial; 1Password/Proton not verified).
- **`SafariExtensionNativeMessagingSuppressionProbe`:** documents repeated-call suppression, coalesced logging, `sessionState` buckets.
- **Acceptance probes:** popup anchor wiring, NM suppression report, PM `login-form.html` fixture.
- **DEBUG menu:** Extensions → Run Safari Extension Dev Diagnostics Report (combined JSON).
- **Guards:** lazy-runtime + popup-anchor + coalescer source guards (no extension-specific branches).
- **Tests:** `SafariExtensionRuntimeDiagnosticsTests` + extended clean-import guards.

### Cycle 11 (2026-06-10)

- **Clean Safari import confirmed:** runtime prefers signed `.appex`; install/enable no longer call
  `patchManifestForWebKit` or `setupExternallyConnectableBridge`.
- **Deleted:** all `ExtensionRuntimeResources/*.js`, `ExtensionRuntimeBundledScript.swift`,
  `ExtensionManager+ExternallyConnectableScripts.swift`, `SumiExternallyConnectableUserScript.swift`.
- **Guards:** `SafariExtensionCleanImportSourceGuardTests` + `scripts/check_safari_extension_clean_import.sh`.
- **Preserved:** Raindrop import/login/save path, per-profile isolation, delete+rescan, private-tab popup block,
  Swift native-messaging relay (`SumiNativeMessagingRelay`).
- **Unsupported APIs:** remain blocked in compatibility diagnostics — not polyfilled.

### Cycle 8 (2026-06-10)

- **`SumiNativeMessagingRelay` architecture:** policy, resolver, connection, port session split.
- **Reclassified `hostApplicationMessageRelay`:** removed from platform blockers; PM targets use
  `companionAppProtocolUnknown` classification instead.
- **DEBUG probe:** Extensions → Run Safari Extension Native Messaging Probe.
- **Tests:** `SumiNativeMessagingRelayTests` + updated acceptance/compatibility/host tests.
- **Build:** `xcodebuild build -scheme Sumi` + Safari extension test suites.
