Type: research
Status: resolved
Blocked by: 01, 03

# Which page-scoped media capabilities does macOS WebKit expose?

## Question

Across Sumi's supported macOS/WebKit range, which public or private APIs on an exact `WKWebView` or its native page media session expose event-driven identity/lifecycle, metadata, playback state, position, duration, playback rate, supported commands, play, pause, previous, next, seek, mute, and PiP? For each surface, what acknowledgement, thread/lifecycle constraints, availability risk, idle work, and fallback behavior apply, and which capabilities can be used without polling or site-specific JavaScript?

## Comments

- The answer must distinguish documented/public API, shipped private selectors, WebKit source-only concepts, and Gecko-only capabilities seen in Zen.
- Prefer Apple headers, WebKit source, and locally linked SDK/runtime evidence; do not infer API existence from Zen.

## Answer

Исследование: [Page-scoped media capabilities in macOS WebKit](/Users/fedaefimov/Code/Sumi/Sumi-webkit/docs/research/webkit-page-media-capabilities.md).

WebKit на target macOS 15.5 даёт точные event-driven page lifecycle/activity signals (`_hasActiveNowPlayingSession`, `_isPlayingAudio`), public aggregate playback snapshot/pause/suspend, private page mute и PiP. Он не экспортирует production `WKWebView` API для supported keys, previous/next/seek, точного playback rate или generic selected-session transport. Полезные identity/duration/position и metadata selectors существуют только в `WKWebViewPrivateForTesting`, без availability contract, поэтому допустимы лишь как runtime-gated enrichment. Текущие private play/pause selectors управляют active controlled video; play fallback выбирает крупнейший видимый main-frame media element, поэтому они не являются надёжным generic Media Session backend. Для первой реализации следует скрыть seek/previous/next и отдельно решить pause/resume semantics: public page-wide pause не имеет generic resume, а paired suspension симметричен, но меняет поведение страницы.
