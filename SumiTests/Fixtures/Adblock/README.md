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
5. Browser runtime: prepared native bundles only; no enhanced runtime path exists in Sumi.app.
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

Use unified protection diagnostics for the capture. If any required
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
