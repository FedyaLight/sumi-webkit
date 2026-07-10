# Sumi Safari Web Extension Compatibility

Last updated: 2026-07-03 (1Password runtime envelope + native-core OS boundary)

## Cycle 27 1Password for Safari: Achievable Runtime + Native-Core OS Wall (2026-07-03)

User installed 1Password desktop + 1Password for Safari and asked for
full end-to-end support. Probed the real installed
`com.1password.safari.extension` (`1Password.appex`, 8.12.x, **MV2**,
persistent background *page*, `permissions`: `<all_urls>` + `nativeMessaging`
+ `scripting` + `tabs` + `storage` + `contextMenus` + `webNavigation` +
`webRequest` + `alarms`, `_execute_browser_action` = Cmd+Shift+X).

### What works in Sumi (proven, `SafariExtension1PasswordRuntimeTests`)

Everything that does not require 1Password's native core:

- Real appex import → validate → enable.
- Cycle-23 site-access seeding grants declared `<all_urls>`; the extension
  has host access to arbitrary pages with no user configuration.
- Every requested API permission granted; `unsupportedAPIs` is empty (no
  1Password API is hidden — MV2, but WebKit's scripting/tabs/etc. are native).
- MV2 persistent background page loads through the wake path.
- Content scripts inject into a real page load
  (`hasInjectedContent(for:)` true through the full tab stack).
- The `browser_action` surface resolves for the tab.

### The one capability that is OS-blocked (definitive finding)

1Password's background reaches its desktop core via
`runtime.connectNative("")` / `sendNativeMessage("", {name:"core", …})`.
The **empty** native-application identifier is the Safari model for "route
to the extension's OWN `.appex` handler" — 1Password's
`NSExtensionPrincipalClass = _Password.SafariWebExtensionHandler`
(`NSExtensionPointIdentifier = com.apple.Safari.web-extension`), which then
talks to the desktop app / local WASM core.

Hosting that appex handler from the browser process was probed directly
against the installed bundle via `NSExtension`/PlugInKit
(`extensionWithURL:` returns a live `EXConcreteExtension`, but
`beginExtensionRequest…` fails):

- **Without the entitlement:** `PlugInKit Code=11 "access to plugin
  com.1password.safari.extension denied: the host does not have the
  \"com.apple.private.can-load-any-content-blocker\" entitlement"`.
- **Claiming the entitlement** in an ad-hoc/dev signature: the process is
  **SIGKILLed by AMFI** (`exit 137`) — Apple-private entitlements are not
  honored for any non-Apple code signature.

So hosting a third-party Safari App Extension's native-messaging handler is
**impossible for any third-party browser** on macOS; only Safari (Apple-
signed, holding the private entitlement) can. 1Password 8's browser
extension is desktop-core-only (no in-extension account login fallback), so
unlock / autofill / dynamic popup cannot function in Sumi — not a Sumi
defect, an OS security boundary. The Chrome/Firefox subprocess host
(`1Password-BrowserSupport` via a `NativeMessagingHosts` manifest) is a
different integration the Safari build does not use (`connectNative("")`,
not a host manifest) and is additionally gated by 1Password's code-signature
browser allowlist.

### Sumi behavior at the boundary

Sumi **rejects** the `connectNative`/`sendNativeMessage` call cleanly (the
worker gets a rejected promise, never a hang), so 1Password's own "can't
connect to the desktop app" UI can take over. Asserted by the test
(`nativeMessageRejectionResult == "rejected"`).

### Same wall applies to

Any Safari appex whose extension talks to its own containing app's handler
via `connectNative("")` for a desktop-core-dependent feature. Bitwarden is
the exception only because it *also* exposes a documented desktop
`native-messaging`/`desktop_proxy` + local-biometric path Sumi adapts
directly (`BitwardenNativeMessagingAdapter`), bypassing the appex handler.

## Cycle 26 Extension Keyboard Commands + Page Context Menus (2026-07-03)

## Cycle 26 Extension Keyboard Commands + Page Context Menus (2026-07-03)

Two Safari-parity chrome surfaces WebKit leaves to the embedding app were
unimplemented: manifest `commands` keyboard shortcuts (e.g. Bitwarden
Cmd+Shift+L autofill) never dispatched, and extension context-menu items
(menus/contextMenus API — e.g. password managers' "autofill login" items)
never appeared in the page menu.

### Fixed

- `ExtensionKeyboardCommandDispatchOwner`: routes keyboard events through
  `WKWebExtensionContext.performCommand(for: NSEvent)` (macOS 15.4+) across
  the current profile's loaded contexts. Wired at the end of
  `KeyboardShortcutManager.handleLocalKeyDown` — Safari dispatch order:
  browser shortcuts first, then extension commands, then the page. Events
  without Command/Control/Option modifiers never touch extension contexts.
- `ExtensionPageContextMenuItemsOwner`: fetches
  `WKWebExtensionContext.menuItems(for:)` for the page's tab adapter at menu
  presentation time (WebKit requires fetch-before-show; items are not
  cacheable). Appended as a trailing separator group in
  `SumiWebPageMenuController.prepare`, gated on tab runtime eligibility
  (private tabs stay excluded).
- Both surfaces enter through `SumiExtensionsModule`
  (`performExtensionKeyboardCommandIfLoaded`, `pageContextMenuItemsIfLoaded`)
  and are no-ops without a loaded, enabled extensions runtime.

### WebKit contract captured

- Command/event matching (WebKit `WebExtensionCommandCocoa.mm`): keyDown,
  non-repeat, command modifier flags must be a subset of the event's flags,
  `activationKey` compared case-insensitively against
  `charactersIgnoringModifiers` (special keys via key-code map). Manifest
  `Alt+Shift+U` ⇒ option+shift + activation key `u`.
- `menuItems(for:)` builds ready-to-host `NSMenuItem`s (targets included) and
  resolves visibility/enablement at fetch time.

### Tests

- `SafariExtensionCommandAndContextMenuTests`:
  `testManifestCommandDispatchesFromKeyboardEvent` (synthetic MV3 manifest
  command dispatches for Alt+Shift+U, declines other keys and plain typing),
  `testBackgroundCreatedMenuItemsSurfaceOnPageContextMenu` (worker-side
  `menus.create` item surfaces through the full tab stack for a real page
  load).
- Regression: site-access, scripting runtime, web-page menu controller, and
  keyboard shortcut store suites pass; architecture guardrails pass.

## Cycle 25 Idempotent Permission Policy Application + Prompt Sheets (2026-07-03)

Field report: Proton Pass popup intermittently showed "permissions not
granted" again after Cycle 23. Root cause: every policy re-application
(context load, popup open, tab reconcile) did a remove-then-regrant sweep
over declared patterns, firing `permissions.onRemoved`/`onAdded` storms into
extension workers; Proton Pass caches such transitions as "permissions
missing" for its popup spotlight.

### Fixed

- `SafariExtensionInstallCapabilityOwner.applyConfiguredSiteAccessPolicy`
  applies the policy as a diff against the context's current grant/deny
  state; re-applying an unchanged policy is a no-op (no permission events).
  WebKit gotchas encoded: grants are add-only (same status with a new
  expiration needs a clear-to-unknown first) and never-expiring grants bridge
  as a far-future date (≥20y ⇒ "no expiration").
- Permission prompts present as window sheets instead of app-modal
  `runModal` (Safari scopes prompts to the window; app-modal also stalled
  every other WebKit delegate completion against the 2-minute deny timeout).

### Tests

- `testUnchangedPolicyReapplicationEmitsNoPermissionEvents` (three unchanged
  re-applications emit zero permission notifications; a real configuration
  change still writes through).

## Cycle 24 Scripting API Enabled for Safari Targets (2026-07-03)

Field report: Proton Pass inline suggestions (login-field dropdown) never
appear while Bitwarden's inline overlay works. Log noise triage: the
`CSInlineDonation`/`SetStoreUpdateService` spam is CoreSpotlight sandbox
noise, and the subframe `didFailProvisionalLoadForFrame code=104`
(content-blocker) on google.com is unrelated third-party-frame blocking.
The load-bearing asymmetry is architectural.

### Root cause

Proton Pass has no static autofill content script: `orchestrator.js` (the
only manifest content script) asks the worker for `LOAD_CONTENT_SCRIPT`, and
the worker bootstraps the entire autofill client via
`browser.scripting.executeScript({files:['client.js']})`, then registers the
inline dropdown's custom elements via MAIN-world
`executeScript({files:['elements.js']})` + `executeScript({func, args})`
(`injection.ts`). Bitwarden ships its overlay through manifest-declared
static content scripts, which is why it worked.

Sumi explicitly blocked that whole path for manifests declaring
`browser_specific_settings.safari`: `shouldDenyAutoGrantForWebKitRuntime`
denied the `scripting` permission and `webKitRuntimeUnsupportedAPIs` hid
`browser.scripting.*` from the runtime — a leftover classification from the
pre-Cycle-13 era (`SafariExtensionInlineUIClassificationCatalog` had Proton
inline UI recorded as `blockedByPlatform/scriptingPermissionDenied`). Real
Safari grants `scripting` (Safari 16.4+), so this was an anti-parity policy.

### Fixed

- Removed the `scripting` auto-grant denial entirely
  (`shouldDenyAutoGrantForWebKitRuntime` and its filter call sites in
  `grantRequestedPermissions` and `promptForPermissions` are gone); Safari
  imports get `scripting` granted like Safari does.
- `webKitRuntimeUnsupportedAPIs` no longer hides `browser.scripting.*` for
  Safari-target manifests. Legacy APIs without a verified WebKit
  implementation (`browser.contentScripts.register`,
  `browser.tabs.executeScript`, `browser.tabs.insertCSS`) stay marked
  unsupported so MV2 extensions keep feature-detect fallbacks.
- Catalogs updated: Proton Pass inline UI reclassified from
  `blockedByPlatform` to `pending` (manual GUI retest), notes rewritten.

### Proven (new automated E2E, `SafariExtensionScriptingRuntimeTests`)

A synthetic Safari-target MV3 extension (browser_specific_settings.safari +
`scripting` + `*://*/*` + service-worker background) drives, through Sumi's
full tab stack (TabManager tab + registered extension runtime + real page
load), the exact Proton bootstrap sequence — worker receives the content
script's message and successfully executes all four WebKit-native calls:

- `scripting.executeScript({target, files})` — isolated-world client.js runs
  in the page;
- `scripting.executeScript({target, world:'MAIN', files})` — MAIN-world
  elements.js runs and can define page-global registration hooks;
- `scripting.executeScript({target, world:'MAIN', func, args})` — argument
  passing into the MAIN world works;
- `scripting.insertCSS({target, files})` — stylesheet applies to the page.

WebKit's native implementation needs no Sumi-side API shim. The probe also
exercises the Cycle 23 seeding path (Safari-appex source with no explicit
site-access configuration → default Allow → host access for the target tab).

### Tests

- New: `SafariExtensionScriptingRuntimeTests.testWorkerDrivenScriptingInjectionMirrorsProtonBootstrap`.
- Updated pins: `SafariExtensionInstallationSecurityTests`
  `testInstallCapabilityOwnerClassifiesWebKitRuntimePolicy` (scripting no
  longer denied/hidden; MV2 legacy APIs still unsupported),
  `SafariExtensionRuntimeDiagnosticsTests` catalog assertions.
- Regression: site-access, installation security, runtime diagnostics,
  inline overlay, autofill runtime, account fork pipeline, action popup,
  profile isolation, storage cleanup planner, origins compatibility, and
  WebView/controller wiring slices pass; guardrails + clean-import audits
  pass; full build succeeds.

### Proven Remaining Gaps

- Manual Proton Pass inline E2E on a real login page (expected: worker
  `LOAD_CONTENT_SCRIPT` → client.js injects → dropdown custom elements
  register → inline suggestion renders on field focus).
- Field logs also showed `tabs.get() Tab not found` (tab 103) from the
  Proton worker; with the scripting path unblocked, re-check whether any
  remaining occurrences are close races on recently closed tabs (benign,
  Safari-console-noise class) or a live tab dropping out of the structural
  lookup (load-bearing — see Cycle 20 contract notes).

## Cycle 23 Site-Access Default Seeding Repair + permissions.request E2E (2026-07-03)

Field report: Proton Pass popup (logged in) shows "Permission denied for
website access. Open the Safari settings…". That string is Proton's
`getHostPermissionsError()` (`useHostPermissions.tsx`), emitted when
`browser.permissions.request({origins})` + `permissions.contains`
re-verification fail. Proton's worker checks
`permissions.contains({origins: manifest.host_permissions})` =
`["*://*/*"]` at startup and broadcasts `PERMISSIONS_UPDATE {granted:false}`,
which drives the popup "Grant permissions" spotlight.

### Root cause (verified against the user's real defaults)

The persisted site-access policy for Proton Pass was
`defaultAccess: ask` + an allow rule `https://*.proton.me/*` (persisted by the
login-time URL permission prompt) + `privateAccessAllowed: true`.
`shouldSeedSafariAppExtensionDefaultAccess` treated only the **empty** `.ask`
shape as unconfigured, so the Safari-appex product default (`Allow`, Cycle 14
"Intentionally Kept") was never seeded once any prompt rule or the
private-browsing toggle had touched the policy record first. With `.ask`
default, `*://*/*` stays ungranted → `permissions.contains` false → Proton
shows the Safari-settings error.

### Fixed

- `SafariExtensionSiteAccessPolicy` gains `defaultAccessConfiguredByUser`
  (backward-compatible decoding; false for all previously persisted records).
  Only the settings-pane `setDefaultSiteAccess` path sets it.
- Seeding now applies default `Allow` whenever `defaultAccess == .ask` and the
  user never explicitly chose a default — per-site rules and the
  private-browsing flag no longer block the seed. Existing rules are
  preserved and still override the default by specificity (explicit denies
  keep winning). Freshly created Safari-appex policies seed `Allow` even when
  legacy prompt decisions migrate in as rules.
- Existing dirty field states self-heal on the next context load
  (`ExtensionRuntimeContextLoader` seeds before policy application).

### WebKit behavior contract captured (permissions API, UI-process sources)

- `permissions.request()` requires a user gesture (web-process check), then
  validates requested origins against manifest-declared patterns, then routes
  through delegate `promptForPermissionMatchPatterns` with **only** the
  patterns in `Requested{Implicitly,Explicitly}` state
  (`WebExtensionContext::needsPermission`); the grant is all-or-none and the
  delegate answer must arrive within a 2-minute WebKit timeout (timeout ⇒
  deny, nothing persisted).
- Explicitly denied (and already granted) patterns are excluded from the
  prompt set; a request with an empty prompt set resolves **true** — the
  Safari "false positive" Proton Pass explicitly works around by re-checking
  `permissions.contains` after every request. Sumi inherits this contract
  unmodified.

### Tests

- `SafariExtensionSiteAccessPolicyTests`:
  - `testSafariAppExtensionDefaultAccessSeedRepairsPromptDirtiedAskPolicy`
    reproduces the exact field policy shape and proves the seed repairs it;
  - `testSafariAppExtensionDefaultAccessSeedKeepsUserConfiguredAskDefault`
    proves a user-chosen `.ask` default survives seeding;
  - `testSafariAppExtensionDefaultAccessSeedAppliesAllowAndPreservesConfiguredRules`
    (updated semantics) proves rules are kept while the default seeds to allow;
  - `testPermissionsRequestAllHostsPromptAllowGrantsAndPersists` — first
    automated end-to-end JS `browser.permissions.request({origins:["*://*/*"]})`
    from a real extension page (evaluateJavaScript = user gesture) through the
    WebKit delegate prompt: Allow resolves the request true, the
    `permissions.contains` re-verification sees the grant, the decision
    persists as a `*://*/*` site rule, and
    `hasRequestedOptionalAccessToAllHosts` flips on;
  - `testPermissionsRequestAllHostsPromptDenyResolvesFalseAndPersists` — Deny
    resolves false, persists, later identical requests do not re-prompt and
    exhibit the documented WebKit false-positive (`request` true,
    `contains` false).
- Regression: site-access, origins compatibility, profile isolation, storage
  cleanup planner, installation security, action popup runtime, autofill
  runtime, and account fork pipeline slices pass;
  `scripts/check_architecture_guardrails.sh` and clean-import audits pass;
  full `xcodebuild build` succeeds.

### Proven Remaining Gaps

- Manual Proton Pass popup E2E after this fix (expected: worker startup
  `permissions.contains` is true, no "Grant permissions" spotlight, no
  Safari-settings error, autofill active on all sites).

## Cycle 22 Popup-Path Fork E2E + Live Fork Diagnostics (2026-07-03)

Field report after Cycle 21: storage stays intact (no more `vnode unlinked`),
companion messaging healthy, Proton onboarding login **works**, but re-login
from the popup still ends in the account page showing "Invalid selector".

### What was established

- **Server semantics confirmed against the real API**:
  `GET https://account.proton.me/api/auth/v4/sessions/forks/<garbage>` (with
  only `x-pm-appversion` set, no cookies) → HTTP 422
  `{"Code":2001,"Error":"Invalid selector"}`. The message is produced solely by
  selector state (unknown/consumed/expired) — cookie problems yield different
  errors. So the field failure means the single-use selector was already dead
  at the extension's *first observable pull*.
- **The real account app broadcasts the fork message to all four Pass
  extension IDs in parallel** (`broadcastMessage`,
  `packages/shared/lib/browser/extension.ts`): three Chromium/Edge store IDs
  plus the composed Safari identifier. WebKit resolves the target context by
  exact `uniqueIdentifier` match in both the web process
  (`WebExtensionAPIWebPageRuntime::sendMessage`) and the UI process
  (`WebExtensionContext::runtimeWebPageSendMessage`); unknown IDs get an empty
  response after a random delay. Verified: the broadcast cannot double-deliver.
- **The popup login path is exactly-once in Sumi**
  (`testAccountForkPipelineFromExtensionCreatedTabWithAccountBroadcast`): the
  probe worker opens the account tab through `browser.tabs.create` (the same
  call Pass's `useRequestFork` makes), the page dispatches the fork via the
  4-ID broadcast, and across two sequential login attempts each selector is
  pulled exactly once, `fork.js` is injected exactly once per page, and the
  page is served exactly once per tab.

### Remaining unknown + the instrument for it

Sumi's own messaging/tab machinery is proven exactly-once for every scenario
we can synthesize, so the selector must be dying server-side between the
page's fork **produce** (`POST /auth/v4/sessions/forks`) and the content
script's **pull**. Leading candidates: a second page instance producing a
newer fork for the same `state` (invalidating the first selector), an SPA
re-produce/retry, or a dropped first exchange followed by a same-selector
retry.

`SafariExtensionAccountForkDiagnosticsUserScript` (DEBUG /
`SUMI_DIAGNOSTICS` builds) now instruments `account.proton.*` pages in the
page world and mirrors events to the unified log, category
`ProtonForkDiagnostics`, marker `ProtonForkDiag`:

- `pageStart` / `pageHide` / `pageShow` with a per-instance ID — detects
  zombie double page instances for one tab;
- `forkApiRequest` / `forkApiResponse` for `/auth/v4/sessions/forks` produce
  and pull calls issued by the page (8-char selector prefixes only);
- `extensionSend` / `extensionResponse` for every page→extension
  `runtime.sendMessage` with elapsed time and response summary — a silent
  WebKit drop shows up as `{"raw":"undefined"}` after a random delay.

One failing login with these logs identifies the broken hop unambiguously:
compare the number of `pageStart` events per tab, the produced selector
prefixes, and which selector prefix the final error response corresponds to.

### Test-harness facts learned (Cycle 22)

- Keep the in-memory SwiftData `ModelContainer` alive in the harness struct:
  `tabs.create` → `openNewTabUsing` → `enabledPersistedExtensionEntities()`
  traps inside SwiftData if the container was deallocated.
- In the windowless test environment, an extension-created normal tab
  materializes its web view but the deferred initial-document handoff never
  issues the navigation (no window coordinator). The e2e drives
  `tab.loadURL(...)` manually after a generous wait and then asserts the page
  was served exactly once, which still catches double-load regressions.

## Cycle 21 Storage Adoption Safety + Test Isolation (2026-07-03)

Field report after Cycle 19/20: clean rebuild still reproduced
`LocalStorage.db … vnode unlinked while in use` under the composed-identifier
directory plus `runtime.sendNativeMessage(): The companion application secure
store operation failed` during Proton login. On-disk inspection of the real
WebKit root proved three distinct defects:

### Root causes

1. **Legacy storage adoption silently no-opped, then stayed armed as a
   directory deleter.** The adoption resolver depended on
   `manager.installedExtensions`, which is empty during early startup loads —
   so the one-time legacy→composed migration never ran (evidence: Bitwarden's
   725 KB `LocalStorage.db` still in the bare-id directory next to a fresh
   empty composed one). Worse, the destructive branch
   (`removeItem(currentDirectory)`) re-armed on **every** context load while a
   data-bearing legacy directory existed, and deleting the composed directory
   in place unlinks SQLite stores WebKit may already hold open — the exact
   "vnode unlinked while in use" corruption.
2. **Unit tests share the user's real WebKit storage root.** Tests are hosted
   inside Sumi.app, so every test-created `WKWebExtensionController` (profile
   XOR-derived identifier) wrote into the user's real
   `~/Library/WebKit/<bundle-id>/WebExtensions/` — one day of test runs leaked
   ~35 controller directories there, and a test that loads a real profile
   would operate on (and clean up) the user's live extension storage while the
   browser is running.
3. **Companion keychain items orphaned by ad-hoc re-signing.** Debug rebuilds
   change the code signature; the Proton companion keychain item written by
   the previous build then fails reads/updates with authorization errors,
   surfacing as `secure store operation failed` on every
   `runtime.sendNativeMessage`.

### Fixed

- `WebExtensionStorageCleanupStore.adoptLegacyStorageDirectoryIfNeeded`:
  - never deletes the composed directory — when it must yield to legacy data
    it is atomically **renamed aside** (`.sumi-replaced-*`), so file
    descriptors WebKit opened after the emptiness check stay valid;
  - always **retires the legacy directory** after the decision (moved into
    place, removed when state-only, or renamed to `.sumi-legacy-retired-*`
    with bytes preserved), so the destructive branch can never re-arm;
  - resolves the storage identity from the load request's
    `sourceKind`/`sourceBundlePath` (`ExtensionRuntimeContextLoader` →
    `adoptLegacyWebExtensionStorageIfNeeded`), not from possibly-unloaded
    `installedExtensions`.
- `ExtensionControllerProvisioningOwner.extensionControllerIdentifier(for:)`
  returns a process-stable **random** identifier in test runs (registered via
  `ExtensionControllerIdentifierOwner` for cross-process cleanup), so tests
  can never collide with a production controller storage root even when they
  load real profiles.
- `KeychainProtonPassSafariCompanionStore` self-heals across code-signature
  changes: authorization-family failures on read are treated as "no stored
  state", and update failures replace the orphaned item (delete + add); all
  failures now log the raw `OSStatus`.

### Tests

- `WebExtensionStorageCleanupPlannerTests`: new
  `testAdoptLegacyRemovesStateOnlyLegacyDirectory`,
  `testAdoptLegacyReplaceSetsComposedDirectoryAsideInsteadOfDeleting`; updated
  `testAdoptLegacyStorageNeverReplacesComposedDirectoryWithData` to assert the
  legacy directory is retired with bytes preserved.
- Regression: fork pipeline E2E, profile isolation, Proton companion adapter,
  message router, site access, runtime identity, import auto-enable,
  Bitwarden adapter, inline overlay suites pass.

### Operational notes

- Old leaked test directories under
  `~/Library/WebKit/<bundle-id>/WebExtensions/` (UUID-only contents) are inert
  but unowned; remove manually while the browser is closed. The real
  controller root is recognizable by bundle-id-named extension directories.
- A user whose pre-migration session still sits in a bare-id legacy directory
  next to an already-used composed directory keeps the composed state (legacy
  is retired, bytes preserved); re-login once in the extension.

## Cycle 20 Account Fork Pipeline Automated E2E (2026-07-03)

Automated end-to-end proof of the Proton Pass Safari login-fork pipeline against
a synthetic MV3 extension and a loopback "account" server
(`SafariExtensionAccountForkPipelineTests`). The probe mirrors Proton's exact
shape: `externally_connectable` page → `runtime.sendMessage(extensionId, …)` →
background broker registered on **both** `runtime.onMessage` and
`runtime.onMessageExternal` (as Proton does, `worker/index.ts`) →
`AUTH_PULL_FORK` relayed via `tabs.sendMessage` to a top-frame content script →
cookie-attached fetch of a **single-use** fork selector.

### Proven (test asserts all of these on Sumi's runtime)

- Page-originated external messages fire **only**
  `runtime.onMessageExternal` — WebKit does not double-dispatch to
  `runtime.onMessage`, so Proton's dual-registered broker handles each fork
  message exactly once (no double consumption of the single-use selector).
- `sender.tab` and `sender.url` are populated for external page messages, so
  Proton's `handleAccountFork` can relay `AUTH_PULL_FORK` back to the sender
  tab.
- The content-script fork pull attaches the account page's session cookie.
- Each selector is pulled from the server exactly once; a replayed selector
  propagates the server's 422 "Invalid selector" back to the page (Proton
  parity for the user-visible failure), and a fresh selector still succeeds
  afterwards.
- `sendResponse` payloads cross the page ↔ extension external boundary in both
  directions (dedicated echo probe).

### WebKit behavior contract captured while diagnosing

`WebExtensionContext::runtimeWebPageSendMessage` (page → extension) resolves
the sending page to a known open tab (`getTab(pageProxyIdentifier)`) and checks
host permission for the page URL **before** dispatching. When the tab is not
resolvable, WebKit answers the page with an **empty response after a random
delay and no error** — the extension never sees the message. On the Sumi side
that resolution runs through `ExtensionTabAdapter.webView(for:)` →
`browserContext.extensionTab(for:)` → `tabManager.tab(for:)`, so any live page
whose tab drops out of the structural tab lookup silently loses
externally-connectable messaging while its content-script one-shot messages
fail with "Tab not found". Keep this in mind for any change to tab
lookup/registration lifecycles.

### Test-harness rules learned

- Wait for `TabManager`'s startup restore
  (`storeRestore.startupRestoreTask`) before creating harness tabs: the restore
  replaces the structural tab state when it lands, and a tab created before
  that point is dropped from the lookup mid-test — reproducing exactly the
  silent external-message loss above (initially misread as a WebKit dispatch
  bug).
- Use `makeSafariExtensionTestBrowserManager` (in-memory startup persistence),
  never a raw `BrowserManager()`, which restores the developer's real session
  asynchronously.

### Proven Remaining Gaps

- Manual Proton Pass login E2E on the real `.appex` + `account.proton.me`
  (single-use selector: an interrupted attempt requires a fresh login from the
  popup). The messaging, storage-identity, and runtime-identifier layers it
  depends on are now all covered by automated tests (Cycles 18–20).

## Cycle 18 Safari Runtime Identifier + Bitwarden Biometric Parity (2026-07-03)

Evidence base:

- Apple documents that a Safari app extension is exposed to web pages and to
  `browser.runtime.id` as `"<bundleIdentifier> (<teamIdentifier>)"`
  ([WWDC22 "What's new in Safari Web Extensions"](https://developer.apple.com/videos/play/wwdc2022/10099/)).
  WebKit routes `externally_connectable` `runtime.sendMessage(extensionId, …)`
  by matching that string against `WKWebExtensionContext.uniqueIdentifier`
  (`WebExtensionControllerProxy::extensionContext(const String&)`).
- The Proton account web app hardcodes
  `me.proton.pass.catalyst.safari-extension (2SB5Z68H26)` for the Pass Safari
  extension (`packages/shared/lib/constants.ts` `EXTENSIONS`), then drives the
  login fork through `runtime.sendMessage` → background `onMessageExternal` →
  `AUTH_PULL_FORK` content script (`fork.js`).
- Bitwarden's `SafariWebExtensionHandler.swift` answers every biometric command
  (`getBiometricsStatus`, `getBiometricsStatusForUser`,
  `authenticateWithBiometrics`, `unlockWithBiometricsForUser`, `biometricUnlock`,
  `biometricUnlockAvailable`) locally via `LAContext` + the `Bitwarden_biometric`
  keychain (account `{userId}_user_biometric`, fallback `key`). Safari never
  launches the desktop app for the extension; `desktop_proxy`/`setupEncryption`
  connects only to an already-running desktop.

### Fixed

- **Proton Pass login (externally_connectable).** Safari app-extension contexts
  now set `WKWebExtensionContext.uniqueIdentifier` to the composed
  `"<bundleId> (<teamId>)"` runtime identifier derived generically from the
  imported `.appex` code signature (`SafariWebExtensionRuntimeIdentity`,
  `configureContextIdentity`). This makes `account.proton.me`'s
  `runtime.sendMessage` reach the extension so the fork/login completes. Non
  Safari sources keep the internal extension id. WebKit data-record cleanup now
  also recognizes the composed identifier.
- **Bitwarden settings no longer launch the desktop app.** The desktop_proxy
  transport no longer calls `NSWorkspace.openApplication` when the desktop is not
  running; the port disconnects (Safari behavior). Local biometric commands keep
  working without the desktop.
- **Bitwarden biometric setup/unlock.** `BitwardenSafariOneShotHandler` now
  performs the real local biometric flow matching `SafariWebExtensionHandler`:
  `LAContext.evaluateAccessControl` prompt plus `Bitwarden_biometric` keychain
  read returning `userKeyB64`, and keychain-derived `getBiometricsStatusForUser`
  (`available` / `notEnabledInConnectedDesktopApp` / `hardwareUnavailable`),
  instead of the previous stub responses. Biometric prompt/keychain access is
  injectable for tests.

### Tests

- `SafariWebExtensionRuntimeIdentityTests` (composed-id format, non-Safari
  returns nil, unsigned path returns nil, installed Proton `.appex` matches the
  web-client contract string).
- `BitwardenNativeMessagingAdapterTests`:
  `testConnectDoesNotLaunchDesktopWhenAppNotRunning`,
  `testBiometricUnlockReturnsUserKeyOnSuccessWithoutDesktopRelay`,
  `testBiometricUnlockReturnsNotEnabledWhenNoStoredKey`,
  `testUnlockWithBiometricsForUserReportsStatusFromKeychain`.
- Regression: site-access policy, profile isolation, Proton companion adapter,
  and context-identity wiring suites pass; clean-import / userscript hot-path /
  prepared-bundle boundary guards and `scripts/check_architecture_guardrails.sh`
  pass; full `xcodebuild build` succeeds.
- Pre-existing unrelated failure:
  `testDelegateNativeMessagingSelectorsAreRestoredForProductionRelay` fails on a
  clean baseline too (order-dependent selector-restore test), not affected here.

### Proven Remaining Gaps

- Manual E2E on real installed apps still required: Proton Pass popup→login on
  `account.proton.me`, and Bitwarden enable-biometric-unlock → Touch ID unlock.
  Bitwarden biometric provisioning still needs the desktop app to have written
  the `Bitwarden_biometric` keychain key (as on Safari); Sumi reads it locally.

## Cycle 19 Storage Identity Continuity (2026-07-03)

Field report after Cycle 18: Proton Pass login progressed past external message
delivery but failed with "Invalid selector", with WebKit logging
`LocalStorage.db … vnode unlinked while in use` under the composed-identifier
storage directory, plus repeated Proton onboarding/extension pages appearing
during normal browsing.

Root causes (all storage-identity fallout from the Cycle 18 identifier change):

- WebKit keys extension storage by `uniqueIdentifier`
  (`WebExtensionController::storageDirectory`), so the composed identifier moved
  storage to a new directory and orphaned the legacy bare-id directory.
- Sumi's storage bookkeeping (`WebExtensionStorageCleanupStore`) still resolved
  directories by the bare extension id: `hasStoredWebExtensionDataCandidate`
  matched the stale legacy directory, so Safari-appex reinstall paths invoked
  `removeStoredWebExtensionData`, which (with composed-id record matching)
  deleted the **live** WebKit store mid-session. Losing `storage.local` mid
  login-fork made Proton re-consume its single-use fork selector → "Invalid
  selector"; every background relaunch with empty storage re-opened Proton
  onboarding pages ("extension pages appearing while browsing").

### Fixed

- `WebExtensionStorageCleanupStore` accepts a storage-directory-name resolver;
  Sumi resolves the WebKit directory name through
  `SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier` (composed for
  `.appex`, internal id otherwise; cached per bundle path).
- One-time legacy adoption: before context load, a legacy bare-id storage
  directory is moved into the composed-identifier directory when the composed
  directory has no real data (`adoptLegacyStorageDirectoryIfNeeded`), preserving
  sessions across the identifier migration. A composed directory that already
  has store files is never replaced.
- Safari parity for reinstall: importing/enabling a Safari app extension no
  longer wipes WebKit extension data (Safari preserves extension state across
  reinstall and containing-app updates). Stale-data cleanup now applies only to
  directory-source installs. Explicit uninstall still removes data after
  teardown.
- Extension-page routing audited: extension pages open only through
  `WKWebExtensionControllerDelegate` tab/window requests
  (`ExtensionRequestedTabLifecycleOwner`, `ExtensionRequestedWindowOpeningOwner`),
  action popups, and the options page — matching Safari. The "extension page on
  normal navigation" symptom was extension-initiated onboarding caused by the
  storage resets above.
- `testDelegateNativeMessagingSelectorsAreRestoredForProductionRelay` fixed: it
  asserted pre-refactor delegate selectors on `ExtensionManager`; native
  messaging delegate callbacks live on `ExtensionControllerDelegateBridge`
  (wired as the controller delegate), and the test now asserts that object.

### Tests

- `WebExtensionStorageCleanupPlannerTests`: resolver-based directory naming,
  legacy adoption when composed missing, replacement of state-only composed
  directories, never replacing composed directories with data, identity-resolver
  no-op.
- Regression: Bitwarden adapter suite (incl. fixed delegate-selector test),
  site-access, install-source, import auto-enable, profile isolation, runtime
  identity, and context-identity wiring suites pass; architecture guardrails and
  clean-import audits pass; full build succeeds.

### Proven Remaining Gaps

- Manual Proton Pass login E2E after storage-continuity fixes. Note the fork
  selector is single-use: a login attempt interrupted mid-flow requires starting
  a fresh login from the popup.
- WebKit logs benign `action.setIcon/setBadgeText Tab not found` for recently
  closed tabs; monitor but currently treated as close races, matching Safari
  console noise.



Sumi targets native Safari Web Extension support through public WebKit APIs
(`WKWebExtension`, `WKWebExtensionContext`, `WKWebExtensionController`,
`WKWebExtensionControllerDelegate`). Chrome MV3 shims, CRX install paths, and
controlled Chrome compatibility popups are out of scope and must not return.

Deployment target is **macOS 15.5**. Local SDK (Xcode macOS SDK) exposes
`WKWebExtension` from **macOS 15.4+** including
`extensionWithAppExtensionBundle:completionHandler:`, while Sumi's current
extension runtime ownership is compiled and tested against macOS 15.5+.

## Modernization Audit Guardrails (2026-06-30)

- Production Swift has no active `ChromeMV3`, CRX installer,
  `sumiExternallyConnectableRuntime`, `SUMI_EC_PAGE_BRIDGE`,
  `setupExternallyConnectableBridge`, or `patchManifestForWebKit` paths.
- Remaining Chrome MV3 / externally-connectable references in this document are
  historical regression guardrails for removed code and should not be treated as
  active runtime architecture.
- `docs/architecture.md` now describes the active Safari-native
  `WKWebExtension` architecture and does not require Chrome MV3 cleanup.

## Cycle 17 Extension Popup Routing and Reload Stability (2026-06-12)

Evidence base:

- Local WebKit 27 SDK headers state that `WKWebExtensionTab.webView(for:)`
  must provide a live `WKWebView` configured with the same
  `WKWebExtensionController` for WebKit to inject or modify page content.
- Safari extension popups that open external `http` / `https` login pages enter
  Safari's normal page/tab pipeline; the opened page is not an extension
  auxiliary popup host.
- Proton Pass declares `account.proton.me` and `pass.proton.me` through
  `externally_connectable.matches` and a login content script, so the generic
  requirement is normal page routing plus granted website access before the
  first login page document is evaluated.

### Fixed

- Extension-owned `safari-web-extension://` popup navigations to external
  `http`, `https`, and `file` URLs now open a normal foreground tab instead of
  creating a child popup-host `WKWebView`.
- Extension-popup routing no longer depends solely on
  `WKNavigationAction.sourceFrame.request.url`; when WebKit does not provide a
  source-frame URL, Sumi falls back to the source `WKWebView` URL and then the
  owning tab URL. This keeps Safari extension login popups on the normal-tab
  path even when WebKit omits source-frame metadata.
- That route preloads the target profile's content-script contexts before the
  normal tab is opened, then registers the materialized tab with WebKit's
  extension runtime.
- User-gesture reconciliation no longer rebuilds a live page merely because a
  content-script rebind marker is pending. Sumi only rebuilds when the live
  `WKWebView` cannot be attached to the correct profile
  `WKWebExtensionController`, which removes the observed reload/blinking loop.
- Live WebView resolution now prefers the tab-owned materialized `WKWebView`
  before consulting browser routing state, matching tabs created outside the
  regular window lookup path.

### Tests

- `SumiNavigationResponderTests.testExtensionPopupExternalCreateWebViewOpensNormalTab`
  proves extension-popup external navigation opens a selected normal tab and
  does not create a popup-host child WebView.
- `SumiNavigationResponderTests.testExtensionPopupExternalCreateWebViewFallsBackToTabURLWhenSourceFrameMissing`
  covers the same route when WebKit omits the source-frame request URL.
- `SafariExtensionWebViewControllerWiringTests.testUserGestureReconcileDoesNotRebuildLivePageForMissedContentScriptBinding`
  proves a missed content-script binding marker does not replace the live page.
- Before the final source-frame fallback patch, the Safari extension regression
  slice passed across site-access policy, origins compatibility, action popup
  runtime, autofill runtime, inline overlay, runtime data-store, profile
  isolation, WebView/controller wiring, native messaging guards, and popup
  navigation responder tests. After the fallback patch, the changed popup
  routing, reload-stability, clean-popup, and installed Proton site-access
  tests pass individually.
- Clean-import audits passed:
  `scripts/check_safari_extension_clean_import.sh`,
  `scripts/check_userscript_hot_paths.sh`,
  `scripts/check_prepared_bundle_runtime_boundary.sh`, and `git diff --check`.
- Build passed with
  `xcodebuild build -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS'`.

### Proven Remaining Gaps

- Manual Proton Pass popup-login E2E still must be re-run in Sumi after this
  build. If the Proton error remains, the next boundary to instrument is native
  WebKit page-to-extension external message delivery after the normal login tab
  has loaded with granted site access.

## Cycle 15 Extension-Created Page Preflight (2026-06-12)

Evidence base:

- Local WebKit 27 SDK headers state that `WKWebExtensionContext.hasInjectedContent`
  and `hasInjectedContent(for:)` still require the context to be loaded and have
  granted website permissions before content is actually injected.
- `WKWebExtensionControllerDelegate.openNewTabUsing` and `openNewWindowUsing`
  completion handlers are app-owned; Sumi can complete them after preparing the
  target profile without faking permissions or patching manifests.

### Fixed

- Extension-created normal `http`, `https`, and `file` tabs now preload the
  target profile's enabled content-script extension contexts before Sumi creates
  the tab and sends WebKit `didOpenTab`.
- Extension-created normal windows use the same preflight before creating the
  first tab in the new window.
- Extension-owned internal pages continue to bypass this normal-page preflight
  and keep their existing `WKWebExtensionContext` override lifecycle.

### Tests

- `SafariExtensionWebViewControllerWiringTests`
  `testExtensionRequestedNormalTabPreloadsContentScriptContextsBeforeOpenNotification`
  and
  `testExtensionRequestedNormalWindowPreloadsContentScriptContextsBeforeOpenNotification`
  prove `didOpenTab` is delivered only after the profile content-script contexts
  are loaded.

### Proven Remaining Gaps

- Proton Pass manual popup/login E2E still needs to be re-run in Sumi. The latest
  user report showed site-access grants alone were not enough; the next generic
  missing boundary found was first-document content-script readiness for
  extension-created normal pages.

## Cycle 14 Site-Access Permissions (2026-06-12)

Evidence base:

- Local WebKit 27 SDK headers confirm that Sumi, as the embedding app, owns
  restore/persist/apply for `WKWebExtensionContext.grantedPermissions`,
  `grantedPermissionMatchPatterns`, `deniedPermissions`,
  `deniedPermissionMatchPatterns`, `hasRequestedOptionalAccessToAllHosts`, and
  `hasAccessToPrivateData`.
- `WKWebExtensionContext.setPermissionStatus(_:for:)` accepts explicit
  granted/denied/unknown status for match patterns, and `WKWebExtension`
  exposes required, optional, and all requested match patterns.
- Safari remains the product reference: extension enablement is separate from
  per-extension website access, configured-site overrides, default access for
  other websites, and explicit private-browsing access.

### Fixed

- Added `SafariExtensionSiteAccessPolicy`, persisted by `(profileId,
  extensionId)`, with default access, configured-site rules, optional
  all-hosts-request state, and private-browsing access.
- Runtime load/enable now applies the persisted policy before WebKit evaluates
  `permissions.contains`, host-origin access, content-script eligibility, action
  popup access, or extension pages.
- Default site access grants declared required, content-script, and optional
  host match patterns through WebKit APIs. This lets Safari extensions that
  check optional host origins see the same Sumi-controlled enabled state instead
  of asking the user to open Safari.app settings.
- Default denied website access restores as explicit WebKit denial for declared
  host patterns; default ask restores as unknown.
- Declared website access is derived from WebKit's match-pattern properties and
  the raw Safari extension manifest host/content-script fields, covering real
  bundles whose broad host access is exposed differently by the SDK.
- Current-site and WebKit permission prompts now persist through the same
  profile-scoped policy, while legacy prompt decisions are used only for
  migration/permission prompts and no longer override match-pattern site policy.
- Configured-site rules are evaluated by specificity so a precise site decision
  can override broad all-host access, matching Safari's per-site settings model.
- Settings now keeps the extension list compact and exposes a Safari-like
  per-extension info popover with warnings, default website access, configured
  website rules, private-browsing access where the manifest allows it, command
  shortcut summaries, and the extension options page.

### Intentionally Kept

- The default website-access state is `Allow`, matching Sumi's prior compatibility
  behavior for imported Safari extensions while making it explicit and persistent
  in Sumi settings.
- `SafariExtensionPermissionsOriginsCompatibility` remains scoped to extension
  pages for Safari/WebKit origin normalization; it is not a site-access grant or
  a manifest patch.

### Tests

- `SafariExtensionSiteAccessPolicyTests` covers optional host grants, profile
  scoping, default deny semantics, persistence across manager reload,
  private-browsing access,
  broad-vs-specific rule precedence, and stale legacy prompt decisions losing to
  the current Sumi site policy.
- The same suite loads the installed Proton Pass Safari `.appex` when present
  and verifies that Sumi's generic policy gives the WebKit context effective
  access to Proton's declared broad host pattern and Proton account/pass URLs.
- Regression slices passed for origins compatibility, profile isolation, lazy
  runtime loading, action popups/Raindrop gates, autofill infrastructure/runtime,
  extension runtime data-store alignment, popup native-messaging lifecycle,
  native-messaging performance guards, and Bitwarden adapter guardrails.
- Clean-import audits passed:
  `scripts/check_safari_extension_clean_import.sh`,
  `scripts/check_userscript_hot_paths.sh`, and
  `scripts/check_prepared_bundle_runtime_boundary.sh`.

### Proven Remaining Gaps

- Proton Pass manual popup E2E has not been re-run in this cycle. The generic
  missing capability found here was configured host access persistence in Sumi;
  the automated installed-bundle check now proves WebKit receives effective
  access for the real Proton Safari extension without Proton-specific runtime
  branches.
- Bitwarden and Raindrop are regression-covered by automated slices; final
  product claims still require the manual checklist below on installed apps.

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
  and [DuckDuckGo `apple-browsers`](https://github.com/duckduckgo/apple-browsers)
  for the bounded Bitwarden desktop-integration path only; Safari-like extension
  import / popup / autofill readiness does not depend on `desktop_proxy`.

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

- Switched extension-owned page URLs to WebKit's native registered
  `safari-web-extension:` custom scheme via `WKWebExtensionContext.baseURL`,
  removing the old public/internal URL rewriting path.
- Updated the inline overlay runtime fixture to assert
  `"runtimeConnectWrapped":false` on the successful resize path.
- Updated auxiliary-surface and modular-performance guards so they no longer keep
  stale externally-connectable handler names as expected filter inputs.

### Deleted

- `SafariExtensionURLSchemeCompatibility.swift`, including the private-SPI URL
  rewriting prelude for translating between `safari-web-extension:` and
  `webkit-extension:`.
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

- `scripts/check_safari_extension_clean_import.sh` now audits absence of the
  deleted runtime-connect wrapper and externally-connectable bridge artifacts.
- `SafariExtensionInlineOverlayRuntimeTests` now proves native WebKit
  `runtime.connect` / `runtime.onConnect` behavior instead of checking for a Sumi
  wrapper marker.
- `BrowserConfigurationNormalTabTests` and `SumiPerformanceModularRegressionTests`
  no longer model deleted bridge markers as auxiliary-filter inputs.
- `scripts/check_userscript_hot_paths.sh` no longer carries an exception for the
  deleted externally-connectable native-messaging file.

### Suspicious Code Intentionally Kept

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
| Architecture doc wording | `docs/architecture.md` | Current architecture wording is Safari-native; no Chrome MV3 cleanup remains |
| Stale test guards | `SumiPerformanceModularRegressionTests` | Assert old `ChromeMV3*` symbols absent (good) |

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

Clean-import audits: `scripts/check_safari_extension_clean_import.sh`.

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
| Permissions | `WKWebExtension.Permission`, match patterns | **Profile-scoped site-access policy (Cycle 14)** — default, configured-site, current-site, optional host, private-browsing, and WebKit prompt paths |
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
| Profile-scoped context identity | **Updated** — stable public `uniqueIdentifier` preserves `runtime.id` / website messaging; scoped `baseURL` prevents cross-profile extension-page collision |
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
| `SumiNativeMessagingRelay` | **Added** — public WebKit delegate bridge; host bundle resolve + `NSWorkspace` wake |
| `SumiNativeMessagingAppResolver` | **Added** — maps extension context / `applicationIdentifier` → host `.app` bundle ID |
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
| Native app messaging (Safari / WebKit delegate) | `sendMessage` / `connectUsing` | macOS 15.4+ | **Implemented — Sumi relay resolves host, wakes via `NSWorkspace`, returns `companionAppProtocolUnknown` until companion IPC is documented** | `SumiNativeMessagingRelayTests`, `SumiNativeMessagingRelayHostResolutionTests` | Bitwarden, 1Password, Proton |
| Externally-connectable page bridge NM | Custom JS shim | N/A | **Removed (Cycle 11)** | `scripts/check_safari_extension_clean_import.sh` | N/A |
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
| Import + enable (manual) | **Yes** | **Yes (automated, Cycle 27)** | Not verified | **Yes** |
| MV2 manifest warning observed (manual) | **Yes** | N/A (MV2, no fatal errors) | Not verified | N/A |
| URL-hub icon + popup (manual) | **Yes** | Action surface resolves; popup gated on native core | Not verified | **Yes** |
| Sign-in session in popup (manual) | **Yes** | **Blocked** (needs desktop core) | Not verified | **Yes** |
| Profile isolation (manual) | Pending | Not verified | Not verified | **Yes** |
| Desktop launch loop (manual) | **No** (suppressed) | **No** (native message rejected cleanly) | Not verified | N/A |
| Native messaging protocol (manual) | **Unknown** (`companionAppProtocolUnknown`) | **OS-blocked** (appex host needs Apple-private entitlement, Cycle 27) | **Unknown** | N/A |
| Content script / autofill (manual) | **Classified** (pending retest) | Content scripts inject; autofill blocked on core | Not verified | N/A |
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

Manual checklist: [`docs/SafariExtensionManualE2E.md`](SafariExtensionManualE2E.md) (documentation-only; not XCTest).

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

Sumi deployment target is **macOS 15.5**.

## Profile isolation (Cycle 10)

Manual repro: Profile A login visible in Profile B popup mapped to
**`extensionControllerSharedAcrossProfiles` + `extensionContextSharedAcrossProfiles`**:
a single global `WKWebExtensionController` and shared `WKWebExtensionContext` instances were
reused across profiles; `switchProfile` only swapped `defaultWebsiteDataStore` on the shared
controller (insufficient — background/service-worker state and extension storage remained shared).

Generic fix (public WebKit APIs only):

- One persistent `WKWebsiteDataStore(forIdentifier: profileId)` per Sumi profile (unchanged).
- One `WKWebExtensionController.Configuration(identifier:)` per profile (distinct from profile store ID).
- One loaded `WKWebExtensionContext` per `(profileId, extensionId)` with stable public `uniqueIdentifier` and a profile-scoped `baseURL`.
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
   import + enable (popup, content scripts, site-access settings, native messaging
   wake). Raindrop login/session fixed generically in Cycle 9 — retest save flow.
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

- **`SumiNativeMessagingRelay`:** resolves host `.app` bundle ID from
  `applicationIdentifier` + Safari import metadata; wakes host via `NSWorkspace.openApplication`.
- **`SumiNativeMessagingAppResolver`:** alias table for PM host IDs
  (`com.8bit.bitwarden` → `com.bitwarden.desktop`, `me.proton.pass.nm` → `me.proton.pass.catalyst`);
  empty identifier falls back to containing app from imported appex path.
- **Delegate wired:** `ExtensionManager+ControllerDelegate` `sendMessage` / `connectUsing` call host
  bridge; `NativeMessagingHandler` retains `WKWebExtension.MessagePort`.
- **Diagnostics:** sanitized buckets only (`extensionId`, direction, host bundle ID, outcome,
  error domain/code) — never message bodies.
- **Tests:** `SumiNativeMessagingRelayHostResolutionTests` and modular regression guards.
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
- **Manual E2E checklist:** `docs/SafariExtensionManualE2E.md` (documentation-only; not XCTest).
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

### Cycle 15 (2026-06-12)

- **Extension-created normal page preflight:** `openNewTabUsing` and
  `openNewWindowUsing` now load enabled content-script contexts for the target
  profile before creating normal pages and notifying WebKit, while internal
  extension pages keep the existing context-override path.
- **Tests:** added tab/window lifecycle coverage proving `didOpenTab` is sent
  with loaded content-script contexts for extension-created normal pages.

### Cycle 16 (2026-06-12)

- **Safari/WebKit contract checked:** WebKit 27 headers define
  `allRequestedMatchPatterns` as websites needed for injected content and for
  receiving messages from websites; `WKWebExtensionContext` permission state is
  app-owned/persisted; `WKWebExtensionTab.webView(for:)` must return a matching
  controller-backed `WKWebView` for content injection/modification to work.
- **Externally-connectable site access:** raw manifest fallback now includes
  `externally_connectable.matches` as declared website access, matching the
  WebKit model for pages allowed to message an extension.
- **No false tab-open success:** `notifyTabOpened` now defers `didOpenTab`
  unless the tab has a live `WKWebView` that can be attached to the correct
  profile `WKWebExtensionController`. Lazy tabs are still lazy; existing
  `setupWebView.beforeInitialLoad` / deferred registration paths retry when the
  WebView exists.
- **Proton compatibility evidence:** installed Proton Pass `.appex` test
  confirms `https://account.proton.me/*` and `https://pass.proton.me/*` are
  declared site-access patterns and are granted by Sumi policy without
  Proton-specific runtime branches.
- **Tests/guards:** targeted site-access and lifecycle tests plus the clean-import
  audit pass; `check_safari_extension_clean_import.sh`,
  `check_userscript_hot_paths.sh`, `check_prepared_bundle_runtime_boundary.sh`,
  and `git diff --check` pass.

### Cycle 14 (2026-06-12)

- **Profile-scoped site-access policy:** added persistent
  `SafariExtensionSiteAccessPolicy` for default website access, configured-site
  rules, optional all-hosts request state, and explicit private-browsing access.
- **WebKit permission source of truth:** install/enable/load and prompt delegates
  now apply policy through `WKWebExtensionContext.setPermissionStatus` for
  declared required, content-script, and optional host match patterns.
- **Manifest fallback for site access:** declared host patterns are unioned from
  WebKit metadata and raw manifest host/content-script fields so real Safari
  bundles with broad host access restore correctly.
- **Settings UI:** extension rows stay compact and use an `info.circle` popover
  for Other Websites, configured website entries, private-browsing access,
  warnings, shortcut summaries, and options-page routing.
- **Legacy migration:** old match-pattern prompt decisions seed new policies but
  no longer override the current Sumi site-access policy.
- **Rule precedence:** specific configured sites override broad all-host rules
  in both Sumi policy evaluation and WebKit permission restoration.
- **Tests:** `SafariExtensionSiteAccessPolicyTests` including an installed
  Proton Pass `.appex` WebKit access check when present, clean-import audits,
  compatibility regression slices, native-messaging guards, and repository guard
  scripts pass.

### Cycle 12 (2026-06-10)

- **`SafariExtensionRuntimeDiagnostics`:** sanitized scripting/content-script/host-permission/tab-frame/popup-anchor status per target.
- **`SafariExtensionManualVerificationCatalog`:** documented manual acceptance matrix (Raindrop verified; Bitwarden partial; 1Password/Proton not verified).
- **`SafariExtensionNativeMessagingSuppressionProbe`:** documents repeated-call suppression, coalesced logging, `sessionState` buckets.
- **Acceptance probes:** popup anchor wiring, NM suppression report, PM `login-form.html` fixture.
- **DEBUG menu:** Extensions → Run Safari Extension Dev Diagnostics Report (combined JSON).
- **Guards:** lazy-runtime, popup-anchor, and coalescer regression checks (no extension-specific branches).
- **Tests:** `SafariExtensionRuntimeDiagnosticsTests` + extended clean-import guards.

### Cycle 11 (2026-06-10)

- **Clean Safari import confirmed:** runtime prefers signed `.appex`; install/enable no longer call
  `patchManifestForWebKit` or `setupExternallyConnectableBridge`.
- **Deleted:** all `ExtensionRuntimeResources/*.js`, `ExtensionRuntimeBundledScript.swift`,
  `ExtensionManager+ExternallyConnectableScripts.swift`, `SumiExternallyConnectableUserScript.swift`.
- **Guards:** `scripts/check_safari_extension_clean_import.sh` plus runtime regression tests.
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
