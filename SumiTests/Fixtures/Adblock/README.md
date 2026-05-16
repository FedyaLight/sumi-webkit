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

Do not compare remembered scores. For every sample, use the same normal tab and
record the exact environment before loading:

1. Visit `https://d3ward.github.io/toolz/adblock.html` and `https://adblock-tester.com/`.
2. Record the selected mode (`off`, `nativeCSS`, or `enhancedRuntime`), selected
   native profile, native compiler identity/version, selected list IDs, and
   whether Tracking Protection is enabled.
3. Call `SumiAdBlockingModule.attachmentDiagnostics(for:)` for the tested URL
   and record stale-generation state, attached native groups, generated rule
   counts, JSON sizes, and cap/discard state.
4. After changing mode, profile, selected lists, or per-site policy, reload the
   page before taking the next score.
5. Keep Native and Enhanced runs separate. Native score runs must remain
   Adblock-JS-free; Enhanced is a distinct opt-in compatibility comparison.

Do not claim an improved score unless the exact URL, mode, profile, compiler,
Tracking Protection state, stale-generation state, and captured diagnostics are
kept with the result.
