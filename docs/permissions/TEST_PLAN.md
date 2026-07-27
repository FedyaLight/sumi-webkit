# Sumi Permission Validation Plan

## Core Invariants

- Normal-tab permission requests route through Sumi bridges and `SumiPermissionCoordinator` before WebKit callbacks, app launches, native panels, or notification delivery.
- Site decisions are keyed by requesting origin, top origin, permission type identity, and profile partition. Display domains and URL query/fragment data are not security identities.
- macOS system authorization state is separate from browser/site decisions. System-blocked results do not become stored site denies.
- One-time and session decisions are memory-only. Persistent stores reject ephemeral profile writes, `filePicker`, and the grouped `cameraAndMicrophone` helper.
- `cameraAndMicrophone` exists for grouped prompt UI and expands to concrete camera and microphone decisions.
- Runtime controls never write stored site decisions.
- File picker is one-time only and never persists a reusable permission.
- External scheme decisions are scoped to site plus normalized scheme.
- Popup background/default-block events and external-scheme attempts are session event state, not stored denies.
- Automatic cleanup removes stale persistent allow decisions only.
- Unsupported content settings for JavaScript, images, automatic downloads, ads, background sync, and sound remain note-only.
- Private WebKit permission symbols stay isolated to approved bridge/provider/delegate files and fail closed when unavailable.

## Unit Test Matrix

| Area | Representative tests | Expected result |
| --- | --- | --- |
| Origins and keys | `SumiPermissionOriginTests`, `SumiPermissionKeyTests`, `SumiPermissionTypeTests` | Origins normalize consistently; top-origin/profile/type partitions are distinct; grouping helpers and external scheme identities are stable. |
| Stores | `DatabasePermissionStoreTests`, `InMemoryPermissionStoreTests` | Persistent, one-time, and session lifetimes behave correctly; ephemeral and non-persistable writes are rejected or downgraded. |
| Queueing | `SumiPermissionQueueTests`, `SumiPermissionCoordinatorTests` | One active query per page, FIFO promotion, duplicate coalescing, and cancellation resolve waiters exactly once. |
| System permissions | `SumiSystemPermissionServiceTests`, `SumiSystemPermissionMappingTests`, `SumiSystemPermissionSnapshotTests`, `SumiSystemPermissionServiceScreenCaptureTests` | Camera, microphone, geolocation, notifications, and screen capture snapshots map deterministically without requesting real TCC authorization in tests. |
| Security policy | `SumiPermissionSecurityContextTests`, `SumiPermissionPolicyResolverTests`, `SumiStorageAccessPolicyTests` | Sensitive permissions require trustworthy origins and allowed browser surfaces; activation requirements and system blockers are deterministic. |
| Runtime controller | `SumiRuntimePermissionControllerTests` | WebKit media runtime state, geolocation provider state, autoplay reload requirements, unsupported operations, and observation lifetimes stay separate from stored decisions. |
| Autoplay policy | `SumiAutoplayPolicyTests`, `SumiAutoplayPermissionStoreTests`, `SumiNavigationResponderTests`, `SumiAutoplayBrowserConfigTests` | Canonical `.autoplay` decisions drive per-navigation WebKit autoplay policy; configuration-level media flags remain fallback-only; old UserDefaults overrides are ignored. |
| Geolocation provider | `SumiGeolocationServiceTests`, `SumiGeolocationProviderTests` | Provider state, pause/resume/revoke behavior, timeout, and page-session cleanup are deterministic. |
| Popup and external sessions | `SumiBlockedPopupStoreTests`, `SumiExternalSchemeSessionStoreTests` | Event state is redacted, session-only, deduplicated, page/tab scoped, and safe to display. |
| File picker presenter | `SumiFilePickerPanelPresenterTests` | Panel configuration is correct without opening a real native panel in unit tests. |
| Cleanup and activity | `SumiPermissionCleanupServiceTests`, `SumiPermissionAutoRevokedActivityTests` | Cleanup is opt-in, profile scoped, stale-allow only, and records auto-revoked activity. |

## Bridge/Integration Test Matrix

| Area | Representative tests | Expected result |
| --- | --- | --- |
| Media and screen capture | `SumiWebKitPermissionBridgeTests`, `SumiScreenCapturePermissionTests` | WebKit media/display requests map to canonical permission types, wait for coordinator settlement, and resolve callbacks once. |
| Geolocation WebKit path | `SumiWebKitGeolocationBridgeTests` | Private delegate/provider callbacks route through coordinator and provider boundaries; provider starts only after site and system permission allow. |
| Notifications | `SumiNotificationPermissionBridgeTests` | Website notifications use coordinator/system state and do not request macOS authorization directly. |
| Popups | `SumiPopupPermissionBridgeTests`, `SumiNavigationResponderTests` | User-activated popups allow by default unless denied; background popups block by default unless allowed; child WebViews are gated behind the bridge. |
| External schemes | `SumiExternalSchemePermissionBridgeTests`, `SumiNavigationResponderTests` | App launches happen only through `SumiExternalAppResolver` after coordinator/session allow; unsupported or blocked schemes do not open. |
| File picker | `SumiFilePickerPermissionBridgeTests` | Normal-tab open panel requests are gated before `NSOpenPanel` creation and stale callbacks deliver no files. |
| Storage access | `SumiStorageAccessPermissionBridgeTests` | Private storage-access callbacks preserve requesting/top origins, prompt or reuse decisions, and fail closed when unavailable. |
| End-to-end flows | `SumiPermissionEndToEndFlowTests`, `SumiPermissionPromptEndToEndTests` | Cross-layer fake flows cover first-time prompts, stored decisions, grouped media, system-blocked outcomes, and current-attempt behavior without live TCC dependencies. |

## UI/View-Model Test Matrix

| Area | Representative tests | Expected result |
| --- | --- | --- |
| URL-bar indicator | `SumiPermissionIndicatorStateTests`, `SumiPermissionIndicatorViewModelTests`, `SumiPermissionIconCatalogTests` | Current-page pending, active, blocked, system-blocked, mixed, and reload-required states render deterministic indicator models and icons. |
| Authorization prompt | `SumiPermissionPromptViewModelTests`, `SumiPermissionPromptPresenterTests`, `SumiPermissionPromptBridgeIntegrationTests` | Prompt candidates are current-page scoped; allow, deny, dismiss, system-step, and settings actions settle through coordinator boundaries. |
| URL hub Permissions submenu | `SumiCurrentSitePermissionsViewModelTests`, `SumiCurrentSitePermissionRowTests`, `SumiURLHubPermissionsSubmenuTests`, `SumiPermissionURLHubIntegrationTests` | Current-site rows read/write through coordinator/store adapters, show runtime sections separately, reset exact keys, and omit unsupported fake controls. |
| Privacy Site Settings | `SumiPermissionSettingsRepositoryTests`, `SumiSiteSettingsViewModelTests`, `SumiSiteSettingsCategoryViewModelTests`, `SumiSiteSettingsSiteDetailViewModelTests`, `SumiSiteSettingsRecentActivityTests`, `SumiPermissionSiteSettingsIntegrationTests`, `SettingsNavigationTests` | Profile-scoped exceptions, category/detail edits, search, recent activity, cleanup status, and reset behavior are exact-key and do not delete site data. |
| Runtime controls | `SumiPermissionRuntimeControlsViewModelTests`, `SumiPermissionRuntimeControlIntegrationTests` | Active camera/microphone/geolocation/autoplay controls operate on current-page runtime state only and do not create stored decisions. |

## Lifecycle/Security Test Matrix

| Area | Representative tests | Expected result |
| --- | --- | --- |
| One-time grants | `SumiPermissionOneTimeLifecycleTests`, `SumiPermissionLifecycleIntegrationTests` | Allow-this-time is page-generation scoped, reused on the same page, and cleared on reload/navigation/tab cleanup. |
| Session grants | `SumiPermissionSessionLifecycleTests` | Session decisions survive page changes within the same profile/session and clear on profile/session cleanup. |
| Stale page cleanup | Bridge tests plus lifecycle integration tests | Awaited WebKit/app callbacks deny or cancel safely when page, tab, WebView, or profile context becomes stale. |
| System-blocked security | Policy, prompt, and end-to-end tests | System denied/restricted/unavailable states surface as explanatory states and never persist site denies. |
| Origin and surface gates | Policy resolver and storage-access tests | Insecure, opaque, internal, extension, MiniWindow, Glance, unknown, same-origin storage access, and malformed requests fail deterministically. |
| Reset boundaries | URL hub and Site Settings integration tests | Permission reset removes permission decisions and permission event state only; cookies, site data, tracking settings, zoom, HTTP auth, and extension data remain untouched. |

## Anti-Abuse And Cleanup Test Matrix

| Area | Representative tests | Expected result |
| --- | --- | --- |
| Prompt cooldowns | `SumiPermissionAntiAbusePolicyTests` | Dismissals create deterministic cooldown/embargo windows scoped by profile, origins, and permission type. |
| Anti-abuse storage | `SumiPermissionAntiAbuseStoreTests` | Events are key scoped, redacted, retained with limits, persistent for persistent profiles, and memory-only for ephemeral profiles. |
| Prompt suppression outcomes | `SumiPermissionPromptSuppressionTests`, coordinator regression coverage | Suppressed requests do not display prompts, do not persist denies, and resolve according to permission-specific bridge contracts. |
| Cleanup service | `SumiPermissionCleanupServiceTests`, `SumiPermissionCleanupIntegrationTests` | Cleanup runs only when enabled, is launch/profile throttled, removes stale persistent allows only, and is idempotent. |
| Cleanup UI/read models | Site Settings and recent activity tests | Toggle/status/recent activity reflect cleanup results without touching unrelated site data. |

## Behavioral Regression Boundaries

Behavioral regression tests protect boundaries that are easy to bypass accidentally:

- `SumiPermissionSourceRegressionTests` verifies active visible normal-tab bridge defaults use prompt settlement, old direct normal-tab paths do not return, old autoplay storage is excluded, settings resets do not delete website data, and runtime controls do not write stored site decisions.
- `SumiPermissionFinalCleanupTests` verifies obsolete fallback terms are gone, system authorization requests are owned by `SumiSystemPermissionService`, file picker and external scheme calls remain behind bridge/presenter/resolver boundaries, private WebKit permission APIs stay in approved files, and permission UI does not own storage/WebKit/system side effects.
- `SumiPermissionDocumentationTests` verifies the stable documentation fixture set exists, the temporary implementation file is absent, prompt-sequence phrases are absent from stable docs, README links are present, license audit markers remain, and architecture/test-plan deferred-work markers remain.

## Manual Validation Matrix

Manual validation fixtures are local-only and intentionally not versioned in this mirror repository. Local pages should be served from localhost, and Storage Access API validation should use a second localhost port to create separate top and embedded origins.

| Area | APIs tested | Required system permission | Expected Sumi UI surface | Expected pass/fail signals | Known limitations |
| --- | --- | --- | --- | --- | --- |
| Media | `getUserMedia`, `enumerateDevices`, Permissions API camera/microphone query | Camera, Microphone | URL-bar indicator, authorization prompt, URL hub Permissions, Privacy Site Settings, Active now controls | Prompt appears; tracks log ended/mute/unmute; one-time clears on reload/navigation; system-blocked is not a site deny | Device labels may be blank before grant; WebKit runtime control support varies. |
| Geolocation | `getCurrentPosition`, `watchPosition`, `clearWatch`, Permissions API geolocation query | Location Services | URL-bar indicator/prompt, URL hub Location row, Active now pause/resume/stop-this-visit, Privacy Site Settings | Coordinates or errors logged; pause/resume affects delivery; reload/navigation clears one-time/provider state | Private provider unavailable paths fail closed. |
| Notifications | `Notification.permission`, `requestPermission`, `new Notification`, Permissions API notifications query | Notifications | URL-bar prompt, URL hub Notifications row, Privacy Site Settings, system-blocked UI | Allow posts when macOS also allows; dismiss resolves `default`; cooldown resolves `default`; stored Block only after explicit deny | ServiceWorker notifications are not tested. |
| Popups | `window.open`, `<a target="_blank">`, delayed/repeated/named/about:blank popups | None | URL-bar blocked indicator, URL hub Pop-ups and redirects row | User-activated opens by default unless blocked; background blocks by default unless allowed; automatic blocks are not saved denies | JavaScript can only infer blocked state from returned window handle. |
| External schemes | `mailto:`, `tel:`, `facetime:`, custom schemes, iframe/background attempts | Installed handler app, where applicable | URL-bar prompt for user-click attempts, URL hub External app links scheme rows, Privacy Site Settings | No app opens before allow; Open this time applies only to current attempt; background blocks; query/fragment redacted | Actual app availability depends on macOS handlers. |
| Autoplay | Generated audible video, muted video, audio element, user-gesture play | None | URL hub Autoplay row, Privacy Site Settings, URL-bar reload-required indicator, Active now reload control | Allow/block/default changes apply after reload/rebuild when required; no autoplay prompt appears | WebKit autoplay behavior can vary; active policy changes apply on navigation-time page preferences, so already-loaded pages may need reload/rebuild. |
| File picker | Single/multiple/accept/directory file inputs, scripted click, navigation while panel open | User file selection in native panel | URL hub File chooser read-only row, current-page event indicator, Privacy Site Settings explanatory activity | Native picker opens only through user-mediated flow; cancel returns no files; names/counts only; no stored decision | Directory input depends on WebKit/macOS attribute support. |
| Storage access | `document.hasStorageAccess`, `document.requestStorageAccess`, cookie read/write in an embedded frame | None | URL-bar prompt, URL hub Embedded content access row, Privacy Site Settings | Allow/deny/dismiss outcomes logged; cookies become visible only when WebKit storage policy permits | Public WebKit API and cookie behavior vary; same-origin/single-port is not a valid test. |
| Screen sharing/display capture | `getDisplayMedia`, Permissions API display-capture query, track logging | Screen Recording | URL-bar prompt before WebKit/system picker, URL hub Screen Sharing row, Privacy Site Settings, system-blocked UI | Display stream or error logged; one-time clears on reload/navigation; no fake runtime stop control appears | Public WebKit exposes no screen-capture runtime stop/revoke state. |
| Site Settings checks | Checklist/manual UI inspection | Depends on rows being inspected | URL hub Permissions, Privacy Site Settings main/list/detail/category/reset/cleanup surfaces | Rows, reset behavior, unsupported content settings note, and recent activity are manually verified | No scripted permission calls. |
| Anti-abuse and cleanup | Checklist/manual UI inspection plus automated injected-clock paths | Depends on pages used | Prompt suppression state, cleanup toggle/status, auto-revoked activity | Repeated dismissals suppress without saved deny; cleanup removes only stale saved Allows through test/injected-clock path | Cleanup timing is mostly unit-test validated; manual 90-day waiting is not practical. |

## Validation Commands

Run format and build checks:

```sh
git diff --check
xcodebuild build -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Run the focused permission documentation and regression tests:

```sh
xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:SumiTests/SumiPermissionDocumentationTests
xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:SumiTests/SumiPermissionSourceRegressionTests
xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:SumiTests/SumiPermissionFinalCleanupTests
```

A full test-suite run is not required for documentation-only permission changes. If a full run is attempted and fails in unrelated WebKit extension tests or stalls, record that separately from the permission documentation gate.

## Remaining Manual-Only Limitations

- Real macOS TCC prompts, device labels, notification delivery, app-handler availability, Screen Recording picker behavior, WebKit Storage Access cookie behavior, and app-level popover focus/placement still require manual validation.
- `SumiUITests` does not yet have deterministic permission injection for fake active queries, repositories, runtime state, or TCC/system authorization.
- ServiceWorker notification delivery remains unsupported unless WebKit exposes a safe app-owned path.
- MiniWindow/Glance and extension permission behavior remain separate from normal-tab website permissions until intentionally integrated.
