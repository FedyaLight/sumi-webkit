Label: wayfinder:map

# Find the architecture for Sumi Sidebar Page Media

## Destination — reached locally

A decision-ready local specification for replacing the current Sidebar Mini Player with a tab-safe, Zen-shaped multi-card Page Media Session architecture, using Atoll/MediaRemote only when it adds safely correlated native capability, with zero disabled cost and tightly bounded CPU, GPU, and RAM while enabled.

## Notes

- The architecture and first production implementation are complete locally; no GitHub or git publishing operation was performed.
- Every session consults `wayfinder`, `grilling`, and `domain-modeling`. The overlay ticket also consults `prototype`, SwiftUI/AppKit patterns, and the Sumi sidebar interaction model.
- Canonical terms live in `CONTEXT.md`: `Sidebar Mini Player`, `Page Media Session`, and `Retained Paused Session`.
- Product constraints already accepted: Sumi pages only; private APIs allowed; tab-scoped WebKit authority; MediaRemote is optional enrichment, never lifecycle or command authority; native capabilities only; no polling; zero disabled cost.
- Visual reference: `/Users/fedaefimov/Code/Sumi/references/Zen`. Adopt its newest-front three-card stack, close affordance, collapsed reservation, and upward overlay, but not its animations, click-through gaps in ownership, per-card timers, or unsafe seek behavior.
- Atoll reference: `https://github.com/Ebullioscopic/Atoll`. Do not copy GPL code or its global untargeted MediaRemote commands.

## Decisions so far

- [Can Atoll safely become the foundation of Sumi's Mini Player?](issues/01-atoll-foundation.md) — No; retain exact WebKit page ownership and reuse only event-stream ideas, with MediaRemote limited to optional enrichment.
- [Which Zen media-card principles should Sumi adopt?](issues/02-zen-card-model.md) — Adopt its page-scoped multi-card stack and overlay geometry while removing per-card timers, animations, unsafe seek semantics, and click-through ambiguity.
- [What product boundary should the Sidebar Page Media effort target?](issues/03-product-boundary.md) — Plan a Sumi-only native-capability player with retained explicit pauses, three-card Zen presentation, exact dismissal semantics, private APIs allowed, and strict resource constraints.
- [Which page-scoped WebKit capabilities are safe?](issues/04-webkit-page-media-capabilities.md) — Use exact WebKit activity/snapshot and public page suspension; omit seek/previous/next.
- [How are sessions owned across residences?](issues/05-session-ownership-across-residences.md) — Window, tab, WebView generation, and WebView object identity form the exact owner.
- [How does the Zen overlay preserve input ownership?](issues/06-zen-overlay-prototype.md) — Fixed collapsed reservation plus an upward overlay using existing AppKit pointer-session routing.
- [What is the lifecycle?](issues/07-session-lifecycle-and-dismissal.md) — Exact playing snapshot or retained explicit pause; dismissal tombstone clears on exact stopped state.
- [What is the command contract?](issues/08-command-and-capability-contract.md) — Addressed, residence-validated, serialized WebKit commands only.
- [Should MediaRemote enrich cards?](issues/09-mediaremote-enrichment-boundary.md) — No; omit it entirely.
- [What is the resource boundary?](issues/10-resource-budget-and-progress-clock.md) — Event-driven, no timers/polling/continuous animation, maximum three materialized cards.
- [What architecture is implemented?](issues/11-final-architecture-boundary.md) — Full snapshot controller, window projection store, Zen-shaped overlay, exact WebKit command bridge.

## Out of scope

- Controlling media owned by Spotify, Music, or any process outside Sumi.
- Sending play, pause, previous, next, or seek to the global system Now Playing owner.
- Copying or adapting GPL-3.0 Atoll implementation code.
- Site-specific DOM adapters, synthetic clicks, or JavaScript polling.
- Production implementation during this wayfinding map; implementation tickets follow after the destination is reached.
