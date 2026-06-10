# Safari Extension Native Messaging Adapter — Manual Acceptance

Last updated: 2026-06-10 (Bitwarden adapter registered; routing diagnostics cycle)

Use with Extensions module enabled. Automated guards live in
`SumiNativeMessagingAdapterRegressionGuardTests` and
`SafariExtensionCleanImportSourceGuardTests`. DEBUG JSON:
**Extensions → Run Safari Extension Native Messaging Probe** or
**Run Safari Extension Dev Diagnostics Report** (`adapterCompatibility` section).

## Preconditions

- macOS 15.7+ with target containing apps installed under `/Applications` when testing PMs.
- No compat JS shims or manifest patching (verified by source guards).
- `SumiNativeMessagingAdapterRegistry.shared` registers `BitwardenNativeMessagingAdapter` on macOS 15.5+.

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
2. With Bitwarden Desktop installed, trigger unlock from the extension popup on `SumiTests/Fixtures/Extensions/login-form.html`.
3. In verbose logs (`SafariNativeMessaging`), confirm routing fields on the first detailed line: `adapterSelected`, `adapterId`, `req`, `resolved`, `launched`, `suppressed`, `protocol`, `handshake`, `failure`, `retry`, `state`.
4. Repeat unlock quickly; confirm Sumi emits one detailed line then `coalesced ext=… repeatCount=… bucket=…` lines — WebKit extension console may still show one NSError per callback (not coalesced by Sumi).
5. Record `realTransportAttempted`, `desktopResolved`, `desktopRunning`, `biometricsStatusProbe` from runtime probe after connect attempt (static probe leaves `realTransportAttempted=false`).
6. Do **not** claim autofill or full Desktop IPC support without observing successful port handshake and biometrics/status replies.

## Native messaging adapter diagnostics (runtime)

After a PM unlock attempt, verbose `SafariNativeMessaging` logs must include **only**:

- `adapterSelected`, `adapterId`, `req` (applicationIdentifier)
- `resolved`, `launched`, `suppressed`
- `protocol`, `handshake`, `autofill`, `failure` buckets
- `retry` (repeated-call count bucket)
- `state` (`SumiNativeMessagingSessionState`)

Must **not** log message bodies, credentials, or storage payloads.

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
