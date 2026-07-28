# Keep page identity stable across residency changes

## Decision

Sumi keeps one lightweight `Tab` identity when a page moves between Live Page and Cold Page residency. Browser-session runtime ports are shared by reference across tabs, WebKit and favicon work stay unmaterialized for cold restored tabs, and the Page Residency controller owns suspension and background-media reconciliation.

Window Page Host keeps one registry for displayed, parked, and compositor-protected hosts. Returning to a Live Page reuses the exact `WKWebView` and host instead of reconstructing presentation state. Evicting a WebView removes every host residence.

`WKWebView.interactionState` may resume a suspended page once within the current app run. It is opaque WebKit state and is never written to durable session storage; after a restart, a Cold Page resumes from its URL and ordinary persisted metadata.

## Rationale

Replacing `Tab` with a separate unloaded object, as DuckDuckGo does, would make Sumi window selection, Launcher Members, Split Groups, drag sessions, and cross-window projections cross an identity conversion boundary. Sharing immutable browser runtime inputs and detaching physical page work gives most of the cold-state benefit without introducing that second identity.

## Consequences

- Live Page activation commits synchronously and must not traverse an activation queue.
- Cold Page materialization is latest-wins; stale work cannot change selection.
- Background restore is capped at 20 total candidates, 10 adjacent candidates per anchor, and 3 concurrent loads, and pauses while foreground content is loading.
- Private WebKit probes are optional observations. They must fail open and never decide correctness.
- Activation display links, resource measurements, and warmup tasks exist only while work is active; idle cost remains zero.
