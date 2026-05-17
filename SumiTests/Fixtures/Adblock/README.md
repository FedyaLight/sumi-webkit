# Adblock Native CSS Manual Validation

This fixture lives under `SumiTests/Fixtures/` because `ManualTests/` is ignored. It validates native WebKit `css-display-none` cosmetic output only; it is not an enhanced runtime, scriptlet, MutationObserver, element picker, or WebExtension fixture.

Manual check:

1. Enable the built-in Adblock module.
2. Set cosmetic mode to `nativeCSS`.
3. Load `native-css-cosmetic.html` with a base URL or test host of `https://example.test/`.
4. Confirm `.ad-banner`, `.sponsored`, and `#sponsor.card[data-ad="1"]` are hidden.
5. Confirm `.keep-visible` remains visible.
6. Switch cosmetic mode to `off` and confirm the cosmetic elements are visible; network blocking is separate.
7. Confirm no Adblock WKUserScript, scriptlet runtime, MutationObserver, JS-to-native bridge handler, or WKWebExtension path is loaded. Existing non-Adblock browser scripts may still be present in normal tabs.

## Native score comparison procedure

Do not compare remembered scores. A score is valid only when the browser state
below is captured immediately before the page load and the page is reloaded
after every profile, mode, list, or site-policy change.

Test pages:

1. `https://adblock.turtlecute.org/` as the current primary manual sample, with caution: record the score, visible test categories, console logs, and diagnostics because the page is still not authoritative.
2. `https://adblock-tester.com/` only as a sanity/reference page; do not use adblock-tester.com as the primary score page if it reports a high score while built-in Adblock is disabled.
3. `https://d3ward.github.io/toolz/adblock.html` as a secondary sample only; it is archived and no longer maintained.

Score pages are not authoritative unless the baseline off/on behavior is
meaningful in the same build and environment. If Adblock disabled and enabled
runs are close together, discard the run and debug attachment state first.

Profiles to measure:

1. `currentDefault` in `nativeCSS`
2. `balancedNative` in `nativeCSS`
3. `highBlockingNative` in `nativeCSS` if update and compile succeed
4. `referenceAdGuardNative` in `nativeCSS` only as a developer-only reference sample

In Debug builds, select comparison profiles from Settings -> Privacy -> Native
Ad Blocking -> Native profile. Release builds must not expose developer-only
profile names or reference profiles. A changed profile persists and marks the
current generation as requiring a manual update; do not record a score until the
manual update has completed and the test page has been reloaded.

Required state for every sample:

1. Built-in Adblock global state: enabled.
2. Per-site Adblock policy for the test page: allowed or inherit-to-enabled.
3. Tracking Protection: disabled.
4. Cosmetic mode: `nativeCSS`.
5. Enhanced runtime: disabled; do a separate comparison if `enhancedRuntime` is tested.
6. Active generation: present and not stale.
7. The selected profile must match the active compiled profile.
8. Native compiler identity and version.
9. Selected native profile.
10. Active compiled native profile.
11. Selected list IDs and active manifest list IDs.
12. Network shard count and attached network shard identifiers.
13. Native CSS shard count and attached native CSS shard identifiers.
14. Total network/native CSS rule counts.
15. Largest shard JSON byte count.
16. Rule cap/discard state.
17. Failed shard identifier or last rebuild error, if any.
18. Date and local time of measurement.
19. Whether the page was reloaded after the last state change.

Use `SumiAdBlockingModule.attachmentDiagnosticsReport(for:)` or
`attachmentDiagnostics(for:)` for the diagnostics capture. If any required
state is missing, stale, globally disabled, per-site disabled, overlapped by
Tracking Protection, or missing expected shards, discard that run and repeat it
after a manual update/recompile plus reload.

In Debug settings, capture the DEBUG Adblock Diagnostics section before and
after each test. For the current tab, also capture URL, normalized site key,
reload-required state, expected shards, attached shards, missing shards, and any
ineligible surface reason.

Do not claim an improved score unless the exact URL, score, mode, native
profile, compiler, Tracking Protection state, Enhanced runtime state, selected
lists, shard diagnostics, timestamp, and reload state are kept with the result.

## 2026-05-17 grouped compiler harness result

`scripts/compare_native_adblock_compilers.sh` now compares the current
adblock-rust compiler with an external, harness-only SafariConverterLib v4.2.2
compiler. The SafariConverterLib path uses neutral `experimentalAdGuardNative`
grouping: `generalAds`, `privacy`, `annoyances`, `regional`, and `custom`.
Each group is converted separately, split into network/native CSS shards, run
through the native CSS safety filter, then compiled and looked up with
`WKContentRuleListStore` before page attachment.

Conditions: `https://adblock.turtlecute.org/`, Tracking Protection off,
`nativeCSS`, enhanced runtime off. Turtlecute did not emit final
`Total / Blocked / Not Blocked` results in the headless WKWebView harness before
timeout, so the fallback `50%` visual value is not a valid blocking score.

| Profile | Backend | Network | Native CSS | Shards N/C | Peak rebuild MB | Page MB | Score | Blank |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `currentDefault` | adblock-rust | 61,438 | 23,671 | 3/1 | 101.3 | 38.2 | not finalized | visible |
| `currentDefault` | SafariConverterLib grouped | 65,330 | 6,075 | 3/1 | 417.3 | 40.6 | not finalized | visible |
| `balancedNative` / ads-only | adblock-rust | 80,986 | 51,979 | 4/3 | 200.4 | 32.9 | not finalized | visible |
| `balancedNative` / ads-only | SafariConverterLib grouped | 86,248 | 19,080 | 4/2 | 645.3 | 43.0 | not finalized | visible |
| `adguard-ads-privacy` | adblock-rust | 273,477 | 52,251 | 11/3 | 375.3 | 58.5 | not finalized | visible |
| `adguard-ads-privacy` | SafariConverterLib grouped | 279,283 | 19,279 | 12/3 | 1,102.8 | 57.9 | not finalized | visible |
| `referenceAdGuardNative` | adblock-rust | 279,678 | 88,964 | 12/5 | 420.6 | 60.0 | not finalized | visible |
| `referenceAdGuardNative` | SafariConverterLib grouped | 285,642 | 40,973 | 13/5 | 1,102.9 | 50.7 | not finalized | visible |

Interpretation: SafariConverterLib reduced native CSS output substantially, but
the current grouped harness peaked much higher during rebuild and did not show a
clear WebKit memory win except on the reference profile. Treat the result as
evidence for more curated-profile work, not as migration evidence.
