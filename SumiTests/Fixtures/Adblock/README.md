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
