# Media Session Pipeline

## Goal

Render one Sumi-native background media card from WebKit now-playing state.

## Owners

- `SumiNativeNowPlayingController.swift`
Elects one background Sumi owner tab, samples native WebKit now-playing state, and routes actions.
- `MediaControlsView.swift`
Pure rendering layer for the sidebar card.
- `Tab`
Provides minimal native playback state (`hasPlayingAudio`, `hasPlayingVideo`, `hasAudioContent`, `isAudioMuted`, `lastMediaActivityAt`) used for candidate discovery and mute retention.

## Rules

- Only regular, non-incognito Sumi tabs are eligible.
- The active foreground tab never renders a sidebar card.
- Card identity is stable per owner tab: `sumi:<tabId>`.
- Metadata comes from native WebKit now-playing APIs only.
- The card is Sumi-only: no external app capture, no system MediaRemote stack.

## Anti-patterns to avoid

- Reintroducing `MediaRemote`, `MPNowPlayingInfoCenter`, or Sumi-owned now-playing export.
- Reintroducing DOM metadata probes or page control bridges for sidebar media.
- Treating the active foreground tab as a sidebar media source.
- Duplicating owner election logic in the view layer.