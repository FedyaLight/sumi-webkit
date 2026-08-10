Type: grilling
Status: resolved
Blocked by: 04, 05, 07

# What command and capability contract prevents wrong-target and optimistic-state races?

## Question

For every candidate native command, decide when the UI exposes it, how it targets the exact Page Media Session, what acknowledgement or observed state transition counts as success, how concurrent or repeated commands serialize, and how owner replacement, navigation, failure, unsupported capability, and late completion affect the card. Define seek-drag semantics without Zen's forced pause/play bug and without sending any command to global Now Playing.

## Comments

- Unsupported controls should not synthesize DOM interaction or remain optimistically enabled.
- The contract must cover play/pause, mute, PiP, previous, next, seek, and progress state independently.

## Answer

All commands are addressed by card ID and revalidate the exact residence before dispatch. Play/pause uses paired public `setAllMediaPlaybackSuspended` on that WKWebView; transport commands serialize per residence and duplicate clicks are ignored while one is in flight. Pause is optimistic only on its own card and rolls back on failure; late completion cannot mutate another card. Mute uses the exact tab/WebView route, PiP remains capability-gated, and `×` uses page-scoped `pauseAllMediaPlayback` followed by clearing suspension.

Seek, previous, next, and progress are not exposed because WebKit has no safe page-scoped contract for them on the supported target. No DOM synthesis or global MediaRemote command is used.
