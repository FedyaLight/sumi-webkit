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

1. `https://adblock-tester.com/`
2. `https://d3ward.github.io/toolz/adblock.html` as a secondary sample only; it is archived and no longer maintained.

Profiles to measure:

1. `currentDefault` in `nativeCSS`
2. `balancedNative` in `nativeCSS`
3. `highBlockingNative` in `nativeCSS` if update and compile succeed
4. `oraLikeNative` in `nativeCSS` only as a developer-only experimental sample

Required state for every sample:

1. Built-in Adblock global state: enabled.
2. Per-site Adblock policy for the test page: allowed or inherit-to-enabled.
3. Tracking Protection: disabled.
4. Cosmetic mode: `nativeCSS`.
5. Enhanced runtime: disabled; do a separate comparison if `enhancedRuntime` is tested.
6. Active generation: present and not stale.
7. Native compiler identity and version.
8. Selected native profile.
9. Selected list IDs.
10. Network shard count and attached network shard identifiers.
11. Native CSS shard count and attached native CSS shard identifiers.
12. Total network/native CSS rule counts.
13. Largest shard JSON byte count.
14. Rule cap/discard state.
15. Failed shard identifier, if any.
16. Date and local time of measurement.
17. Whether the page was reloaded after the last state change.

Use `SumiAdBlockingModule.attachmentDiagnosticsReport(for:)` or
`attachmentDiagnostics(for:)` for the diagnostics capture. If any required
state is missing, stale, globally disabled, per-site disabled, overlapped by
Tracking Protection, or missing expected shards, discard that run and repeat it
after a manual update/recompile plus reload.

Do not claim an improved score unless the exact URL, score, mode, native
profile, compiler, Tracking Protection state, Enhanced runtime state, selected
lists, shard diagnostics, timestamp, and reload state are kept with the result.
