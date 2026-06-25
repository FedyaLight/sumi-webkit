# Safari Extension Native Messaging Adapter — Manual Acceptance

Last updated: 2026-06-11 (native WebKit cleanup; stale externally-connectable bridge removed)

Use with Extensions module enabled. Automated guards live in
`SumiNativeMessagingAdapterRegressionGuardTests` and
`SafariExtensionCleanImportSourceGuardTests`. DEBUG JSON:
**Extensions → Run Safari Extension Native Messaging Probe** or
**Run Safari Extension Dev Diagnostics Report** (`adapterCompatibility` section).

Public references: Apple
[Safari native app messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension),
WebKit `WKWebExtensionControllerDelegate` send/connect callbacks, Bitwarden
[desktop_proxy native messaging documentation](https://contributing.bitwarden.com/getting-started/clients/browser/biometric/),
and DuckDuckGo [`apple-browsers`](https://github.com/duckduckgo/apple-browsers).

## Preconditions

- macOS 15.7+ with target containing apps installed under `/Applications` when testing PMs.
- No compat JS shims or manifest patching (verified by source guards).
- No `SafariExtensionRuntimeConnectCompatibility` wrapper or externally-connectable page bridge.
  `runtime.connect` / `runtime.onConnect` must be native WebKit behavior, verified by
  `SafariExtensionInlineOverlayRuntimeTests`.
- `SumiNativeMessagingAdapterRegistry.shared` registers `BitwardenNativeMessagingAdapter` on macOS 15.5+.

## Current Implementation Boundary

- Native messaging enters Sumi through `WKWebExtensionControllerDelegate`
  `sendMessage` and `connectUsing` callbacks, backed by `WKWebExtension.MessagePort`.
- The deleted externally-connectable bridge is not part of native messaging,
  popup lifecycle, or manual password-manager verification.
- Bitwarden's `desktop_proxy` adapter is a bounded desktop-integration path for
  native messaging / biometrics probes. It is not required for base Safari-like
  extension import, popup, or autofill UI readiness. 1Password and Proton Pass
  intentionally remain adapter-unavailable / protocol-unknown until a documented
  companion-app protocol exists.
- Diagnostics may record identifiers, routing buckets, launch/suppression flags,
  retry buckets, and session state. They must not record credentials, tokens,
  cookies, form values, or native-message payload bodies.

## Per-target manual checklist

| Step | Bitwarden | 1Password | Proton Pass | Raindrop |
|------|-----------|-----------|-------------|----------|
| Import + enable `.appex` | ☐ | ☐ | ☐ | ☐ |
| URL-hub action icon on `https://` | ☐ | ☐ | ☐ | ☐ |
| Popup non-empty (`popupLoadStatus` → `loaded`) | ☐ | ☐ | ☐ | ☐ |
| Profile isolation (login in A not visible in B) | ☐ | ☐ | ☐ | ☐ |
| PM autofill / field icons on login form | ☐ | ☐ | ☐ | N/A |
| Native unlock attempt (host may wake once) | ☐ | ☐ | ☐ | N/A |
| No desktop launch loop on repeated unlock | ☐ | ☐ | ☐ | N/A |
| Save flow without host relay | N/A | N/A | N/A | ☐ |

### Bitwarden-specific manual steps (adapter registered)

1. Import + enable Bitwarden Safari extension; confirm `adapterCompatibility` row shows `adapterSelected=true`, `adapterIdentifier=com.bitwarden.desktop.native-messaging`, `protocolStatus=adapterReady`.
2. Start `scripts/serve_autofill_fixtures.sh` and open `http://127.0.0.1:8765/login-basic.html`; with Bitwarden Desktop installed, trigger unlock and inline suggestion UI from the extension popup/page.
3. In verbose logs (`SafariNativeMessaging`), confirm routing fields on the first detailed line: `adapterSelected`, `adapterId`, `req`, `resolved`, `launched`, `suppressed`, `protocol`, `handshake`, `failure`, `retry`, `state`.
4. Repeat unlock quickly; confirm Sumi emits one detailed line then `coalesced ext=… repeatCount=… bucket=…` lines; WebKit extension console may still show one NSError per callback (not coalesced by Sumi).
5. Record `realTransportAttempted`, `desktopResolved`, `desktopRunning`, `biometricsStatusProbe` from runtime probe after connect attempt (static probe leaves `realTransportAttempted=false`).
6. Do **not** claim autofill, inline suggestion UI, or full Desktop IPC support without observing successful port handshake and biometrics/status replies.

### Raindrop manual steps

1. Import + enable the Raindrop Safari extension from the containing app.
2. Open a normal, non-private tab on an `https://` page; confirm the URL-hub
   action appears and the popup loads non-empty.
3. Log in using Raindrop's normal web flow, save the current page, close and
   reopen the popup, and confirm the saved/logged-in state is profile-scoped.

### 1Password / Proton Pass manual readiness steps

1. Import + enable the Safari extension from the containing app.
2. Open `http://127.0.0.1:8765/login-basic.html` from
   `scripts/serve_autofill_fixtures.sh`; confirm popup/login/autofill UI readiness.
3. Trigger native unlock once; expected Sumi result without a dedicated adapter is
   `adapterUnavailable` or `companionAppProtocolUnknown`, with repeated launch
   attempts suppressed.
4. Record only diagnostic buckets and visible UI observations. Do not record
   passwords, tokens, cookies, form values, or native-message payloads.

## Native messaging adapter diagnostics (runtime)

After a PM unlock attempt, verbose `SafariNativeMessaging` logs must include **only**:

- `adapterSelected`, `adapterId`, `req` (applicationIdentifier)
- `resolved`, `launched`, `suppressed`
- `protocol`, `handshake`, `autofill`, `failure` buckets
- `retry` (repeated-call count bucket)
- `state` (`SumiNativeMessagingSessionState`)

Must **not** log message bodies, credentials, or storage payloads.

### Proton Pass unsupported companion messages

When Proton Pass reaches Sumi's Safari `application.id` companion adapter with an
unsupported message, capture the metadata-only boundary line with:

```bash
log stream --style compact --level info --predicate 'subsystem == "com.sumi.browser" AND (category == "ProtonCompanion" OR eventMessage CONTAINS "ProtonCompanionUnsupported")'
```

For a completed run, use the same predicate with `log show --last 10m --style compact --predicate ...`.
The marker is `ProtonCompanionUnsupported` and includes only payload class, parse
mode, top-level keys, selected type, parse failure reason, and redacted profile /
extension buckets.

### Bitwarden (adapter registered)

- `adapterSelected=true`, `adapterId=com.bitwarden.desktop.native-messaging`
- `failure=none` when imported/enabled and desktop installed; otherwise `hostNotFound`, `relayTimeout`, `unknown`, or policy buckets — **not** `companionAppProtocolUnknown` when adapter is selected
- `protocol=adapterReady` (static probe) or `relayActive` / `relayPending` after runtime connect
- `handshake=notAttempted` in static probe; `completed` / `failed` after port session
- `desktopLaunchLoop=no` (manual catalog)

### 1Password / Proton Pass (no adapter yet)

- `adapterSelected=false`, `adapterId=-`
- `failure=adapterUnavailable` or `failure=companionAppProtocolUnknown`
- `protocol=protocolUnknown` or `protocol=suppressed`
- `handshake=suppressed` after first attempt (loop guard)

## WebKit console vs Sumi diagnostics (coalescing)

| Surface | Repeated unlock behavior |
|---------|--------------------------|
| WebKit extension popup / background console | May log one native-messaging NSError per delegate callback |
| Sumi `SafariNativeMessaging` verbose log | First failure per session key is detailed; duplicates coalesce to `coalesced ext=… repeatCount=… bucket=…` with `suppressed=true` |

Treat WebKit console noise and Sumi diagnostic buckets as complementary — compare `failure` / `retry` buckets in Sumi, not raw WebKit error counts.

## DEBUG probe expectations (`adapterCompatibility`)

| Target | `adapterSelected` | `protocolStatus` | `failureBucket` (imported+enabled) | `launchSuppressionExpected` |
|--------|-------------------|------------------|-----------------------------------|----------------------------|
| Bitwarden | `true` | `adapterReady` | `none` | `true` |
| 1Password | `false` | `protocolUnknown` | `companionAppProtocolUnknown` | `true` |
| Proton Pass | `false` | `protocolUnknown` | `companionAppProtocolUnknown` | `true` |
| Raindrop | `false` | `notApplicable` | `none` | `false` |

Routing fields on `adapterCompatibility` rows (password managers):

- `realTransportAttempted` — `false` in static probe; `true` only after runtime port connect
- `desktopResolved` — host bundle resolved
- `desktopRunning` — `NSRunningApplication` probe for host bundle
- `desktopLaunchAttempted` / `desktopLaunchSuppressed` — runtime launch policy (static probe: `false` / adapter-dependent)
- `biometricsStatusProbe` — `notAttempted` when adapter registered; `notApplicable` without adapter
- `repeatedCallCountBucket` — `none` in static probe; maps to `retry` in runtime logs

## Regression guards (CI)

- No JS shim files in adapter layer or `ExtensionRuntimeResources/*.js`
- No `patchManifestForWebKit` in Safari import/runtime path
- Clean `.appex` load via `WKWebExtension(appExtensionBundle:)`
- Lazy profile runtime (no eager `ensureEnabledExtensionsLoaded` on profile switch)
- Popup anchor wiring generic (no per-vendor branches in loop guard / coalescer)
- Native messaging loop guard suppresses repeated launches for unsupported protocols; Bitwarden uses supported-relay path (no cooldown suppression)

## Fixture reference

PM autofill manual probe: `SumiTests/Fixtures/Extensions/login-form.html`

Protocol adapter unit tests: `SumiTests/SumiNativeMessagingProtocolAdapterTests.swift`
(uses `SumiNativeMessagingFakePublicAdapter` — not production Bitwarden).

Bitwarden adapter + fake transport: `SumiTests/BitwardenNativeMessagingAdapterTests.swift`
