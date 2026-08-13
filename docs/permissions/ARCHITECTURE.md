# Sumi Permission Architecture

## Overview

Sumi's permission system routes normal-tab website and app permission requests through browser-owned bridges and a central coordinator before WebKit callbacks, app launches, native panels, or notification delivery are resolved.

The architecture separates four concerns:

- site permission decisions keyed by requesting origin, top origin, permission type, and profile partition;
- macOS system authorization state for TCC-backed capabilities;
- WebKit and app callback adapters that resolve each request exactly once;
- UI surfaces that display and settle permission state without directly owning storage or WebKit callbacks.

## Implemented Normal-Tab Permission Scope

The implemented normal-tab scope covers:

- camera;
- microphone;
- grouped camera + microphone prompt UI, stored as concrete camera and microphone decisions;
- geolocation;
- notifications;
- screenCapture;
- popups;
- externalScheme;
- autoplay;
- filePicker;
- storageAccess.

Glance and MiniWindow surfaces are fail-closed for permission prompt UI (`canPresentPromptUI` is false; sensitive permissions are denied by policy). Full MiniWindow/Glance permission integration (beyond fail-closed gating), extension permission bridging/UI, optional extra content settings, deterministic permission XCUITest injection, and ServiceWorker notification support remain deferred.

## Permission Model And Storage

`SumiPermissionCoordinator` owns permission decision flow. It runs security policy gates, checks one-time/session memory, reads persistent profile storage, exposes active authorization queries, queues duplicate or later requests, records prompt and anti-abuse events, and resolves all waiters exactly once.

`DatabasePermissionStore` stores persistent decisions in `Sumi.sqlite` for persistent profiles only. It rejects ephemeral profile keys, one-time/session decisions, `filePicker`, and the grouping helper `cameraAndMicrophone`.

`InMemoryPermissionStore` stores one-time and session decisions. One-time identities include the transient page id, while persistent identities exclude it. Session decisions are profile/session scoped and memory-only.

`SumiPermissionKey` uses normalized requesting origin, top origin, permission type identity, and profile partition id. Display strings, renderer-provided labels, URL query strings, and URL fragments are not security identities.

`SumiPermissionGrantLifecycleController` clears one-time grants, session/event state, geolocation provider sessions, pending file pickers, blocked popup records, external scheme attempts, and indicator events on navigation, tab/WebView cleanup, profile/session cleanup, and current-site reset.

`SumiPermissionCleanupService` removes only eligible stale persistent allow decisions and records auto-revoked recent activity. It does not delete cookies, website data, tracking overrides, zoom settings, HTTP auth, extension data, or WebKit data-store contents.

## System Permission Boundary

macOS authorization state is represented by `SumiSystemPermissionService`. It covers camera, microphone, geolocation, notifications, and screen capture.

Security policy and coordinator code inspect system snapshots only. They do not request macOS authorization or open System Settings.

The permission prompt view model is the only UI path that may call `requestAuthorization(for:)`, and only after the user selects an allow action for a permission that requires a system step. System-blocked outcomes are explanatory browser states, not stored site denies.

## WebKit Bridge Flows

Bridges are callback adapters. They build `SumiPermissionSecurityContext`, call the coordinator, record approved UI events through dedicated event stores, and resolve WebKit or app callbacks exactly once.

| Area | Implemented owner | Boundary |
| --- | --- | --- |
| Camera and microphone | `SumiWebKitPermissionBridge` | Public and legacy WebKit media callbacks map WebKit media types to `.camera`, `.microphone`, or grouped UI requests, then wait for coordinator settlement on active visible normal tabs. |
| Screen capture | `SumiWebKitPermissionBridge` plus `SumiWebKitDisplayCaptureRequest` | Private display-capture selectors and legacy display-device bits map to canonical `.screenCapture`; runtime stop controls remain absent unless WebKit exposes a real API. |
| Geolocation | `SumiWebKitGeolocationBridge`, `SumiGeolocationProvider`, `SumiGeolocationService` | Private WebKit delegate/provider ABI is isolated; location is delivered only after both macOS/system and site decisions allow. |
| Notifications | `SumiNotificationPermissionBridge`, `SumiNotificationService` | Website notifications use coordinator/site/system state. Delivery service is not permission truth. |
| Popups | `SumiPopupPermissionBridge`, `SumiBlockedPopupStore` | User-activated popups allow by default unless denied. Background/script popups block by default unless allowed and record session-only blocked state. |
| External app schemes | `SumiExternalSchemePermissionBridge`, `SumiExternalAppResolver`, `SumiExternalSchemeSessionStore` | Active normal-tab main-frame callbacks may prompt without a surviving WebKit gesture so OAuth redirects can complete. Background frames and non-normal surfaces fail closed, automatic attempts are limited per page, and `NSWorkspace.open` remains behind the resolver and coordinator decision. |
| Autoplay | `SumiAutoplayPolicyStoreAdapter`, `SumiAutoplayPolicyNavigationResponder`, `BrowserConfig` fallback, runtime reload requirement | `.autoplay` decisions are canonical store records and are applied through navigation-time `WKWebpagePreferences`. Old `settings.sitePermissionOverrides.autoplay` data is ignored and not migrated. |
| File picker | `SumiFilePickerPermissionBridge`, `SumiFilePickerPanelPresenter` | Normal-tab `runOpenPanel` gates through the bridge before the presenter creates `NSOpenPanel`. File picker decisions are one-time only and never persist. |
| Storage access | `SumiStorageAccessPermissionBridge` | Private WebKit storage-access selectors map to `.storageAccess` coordinator decisions and fail closed when unavailable. |

Bridges must not write the database directly, call macOS system authorization APIs directly, mutate SwiftUI state directly, use display domains as security keys, persist raw URL query/fragment when a redacted representation is sufficient, or persist site deny decisions for system-blocked, suppressed, cancelled, stale-page, unavailable-private-API, or background default-block outcomes.

Active visible normal-tab promptable requests use prompt-settlement defaults. Fail-closed fallback strategies remain only for headless tests, no-window/no-presenter states, background requests where prompting is unsafe, stale page/tab/WebView cases, and unavailable private WebKit symbols:

- `promptPresenterUnavailableDeny`
- `promptPresenterUnavailableBlock`
- `backgroundPromptUnavailableBlock`
- documented system-blocked and cancel reasons such as `systemBlockedCancel`

## UI Surfaces

Permission UI is split by scope:

- URL-bar dynamic indicator: current-page pending, active, blocked, system-blocked, reload-required, popup/external/file/notification/storage events.
- URL-bar anchored authorization prompt: promptable active normal-tab queries and system-blocked explanatory states.
- URL hub current-site Permissions submenu: current-tab/site decisions, current-page runtime controls, and current-session event summaries.
- Privacy Settings -> Site Settings: profile-scoped persistent exceptions, recent activity, category pages, site detail pages, unsupported-content note, cleanup status/toggle, and site permission reset.

SwiftUI views do not write `Sumi.sqlite` directly, call WebKit permission APIs, or request macOS authorization directly. URL hub reset and Privacy Site Settings reset remove permission decisions only; site data deletion remains a separate explicit data-delete action.

Unsupported content settings for JavaScript, images, automatic downloads, ads, background sync, and sound remain note-only. They are not exposed as fake permission controls.

## Runtime Controls

Runtime controls are current-page controls and never write stored site decisions.

Camera and microphone runtime state comes from WebKit capture state where public API exists. Controls may mute, unmute, stop, or refresh current-page state through `SumiRuntimePermissionController`.

Geolocation runtime controls are provider/page-session controls. They may pause, resume, or stop location sharing for the current visit without writing a persistent deny.

Autoplay enforcement is navigation oriented. Normal tabs apply the current site policy through `WKWebpagePreferences` before WebKit commits a main-frame navigation; configuration-level media flags remain fallback-only. A changed policy for an already-loaded current site can expose a reload/rebuild-required state and an explicit reload action.

Notifications, popups, external schemes, storage access, and file picker do not have active device runtime controls. Screen capture does not expose a fake stop control because public WebKit does not expose a screen-sharing runtime stop API.

## One-Time/Session Lifecycle

One-time decisions are page-generation scoped. Reload, main-frame navigation, tab close, WebView cleanup, and current-site reset clear them.

Session decisions are profile/session scoped and memory-only. Profile cleanup and session cleanup clear them. Ephemeral profiles use one-time/session decisions and do not write persistent records.

File picker is always one-time and never persisted. Grouped camera + microphone decisions are represented for prompt UI, then expanded to concrete camera and microphone decisions for storage and runtime behavior.

## Anti-Abuse And Automatic Cleanup

Prompt anti-abuse state is local, profile/key scoped, and network-free. Repeated dismissals can suppress prompt UI for a cooldown or embargo window. Suppressed requests resolve through the bridge contract without writing persistent deny decisions. Explicit allow or exact-key reset clears suppression for that key.

Automatic cleanup is opt-in. When enabled, it removes stale persistent allow decisions only, scoped by exact permission key and profile. It preserves persistent deny and ask decisions, one-time/session state, website data, cookies, tracking settings, zoom, HTTP auth, extension data, and WebKit data stores.

## Manual Validation

Manual validation fixtures are local-only and intentionally not versioned in this mirror repository. Any local permission pages must be served from localhost because most permission APIs require a secure context and Sumi treats localhost origins as trusted local development origins.

Manual coverage should include media, geolocation, notifications, popups, external schemes, autoplay, file picker, storage access, screen capture, URL hub/Site Settings checks, anti-abuse, and cleanup behavior. Storage Access API validation uses two localhost ports to create separate top and embedded origins.

## Automated Validation

Automated coverage is layered:

- store/coordinator/unit tests for keys, lifetimes, profile partitioning, system snapshots, policy gates, queueing, prompt settlement, anti-abuse, cleanup, autoplay, and lifecycle;
- bridge and integration tests for media/screen, geolocation/provider, website notifications, popups, external schemes, file picker, and storage access;
- view-model tests for URL-bar indicator, prompt model, URL hub current-site permissions, Privacy Site Settings, runtime controls, recent activity, anti-abuse, and cleanup;
- source-level regression guards for old bypass paths, private API isolation, system authorization ownership, direct panel/open ownership, old autoplay path exclusion, UI side-effect boundaries, documentation fixtures, and license markers;
- manual localhost pages for real device, TCC, WebKit, app-handler, and popover behavior that cannot be deterministically automated yet.

## Private WebKit API Boundaries And Known Limitations

Sumi uses private WebKit surfaces only where the public macOS SDK does not expose a normal-tab permission callback:

- geolocation provider ABI and provider manager symbols;
- private geolocation delegate selectors;
- private storage-access delegate selectors;
- private display/screen-capture selectors and display-capture decision values.

Each private boundary is isolated to a narrow production file/module, runtime availability is checked, unavailable symbols fail closed, and source regression tests guard that the symbols do not spread into UI/settings code.

Known limitations:

- The active SDK has no public website-notification delegate API; website notifications use a Sumi-owned JavaScript bridge.
- Screen Recording preflight is Boolean-only; `false` cannot distinguish not-determined from denied until the user takes a system prompt/settings action.
- Public WebKit exposes camera/microphone runtime state, but not a screen-sharing runtime stop API.
- Storage Access API behavior depends on WebKit's private callback availability and cookie policy behavior.
- ServiceWorker `showNotification()` remains unsupported until a safe app-owned WebKit path exists.

## Deferred Work

The following areas are intentionally outside the implemented normal-tab permission scope:

- Full MiniWindow/Glance permission integration beyond fail-closed gating. Their direct OAuth media/file picker behavior remains separate auxiliary-surface behavior and should not be treated as normal-tab architecture.
- Extension permission bridging/UI. `WKWebExtensionControllerDelegate` permission behavior remains separate from website permissions.
- Deterministic permission XCUITest injection harness for fake active queries, repositories, and runtime state.
- Optional future content settings for JavaScript, images, automatic downloads, ads, background sync, and sound.
- Optional ServiceWorker notification support if WebKit exposes a safe app-owned path.
- Any future WebKit bridge for new permission types.
