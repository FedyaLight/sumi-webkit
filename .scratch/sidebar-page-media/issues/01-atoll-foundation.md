Type: research
Status: resolved
Blocked by: None

# Can Atoll safely become the foundation of Sumi's Mini Player?

## Question

Can Atoll's private MediaRemote event stream and command path be filtered to Sumi and safely correlated and routed to one exact Sumi tab/Page Media Session, including play, pause, previous, next, and seek, without polling or unacceptable process/memory cost?

## Answer

No. Atoll observes the single global system Now Playing projection and exposes application bundle identity and metadata, not Sumi Durable Page Identity, WebView Residence generation, or a target/session token. Its play, pause, and seek calls target whichever global session is current at command time and provide no acknowledgement, so an app-level Sumi filter cannot prevent another Sumi tab or a newly current application from receiving the command.

Useful ideas are event-driven full snapshots/diffs, identity resets, and timestamp-plus-playback-rate progress derivation. Sumi must independently implement those ideas around its exact page-scoped WebKit owner. MediaRemote may later be considered only as optional, safely correlated enrichment.

Research asset: [Atoll mini-player architecture](../../../docs/research/atoll-miniplayer-architecture.md).
