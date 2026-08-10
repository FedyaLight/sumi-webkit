Type: research
Status: resolved
Blocked by: None

# Which Zen media-card principles should Sumi adopt?

## Question

What exact identity, ordering, stack, dismissal, overlay, hit-testing, native-capability, progress, and resource behavior does the local Zen media controller implement, and which principles should Sumi adopt or reject?

## Answer

Zen binds each card to a page-scoped Gecko `MediaController`, keeps one card per browser, orders newest created first, presents at most three cards, pauses and destroys only the dismissed card, reserves collapsed card/peek height, and expands the stack upward over tabs. Sumi adopts that visible model, with lightweight records rather than materialized views beyond the first three.

Sumi rejects Zen's separate 1 Hz timer per playing card, forced pause/play around seek, implicit click-through behavior, and animated geometry. Sumi requires exact card hit ownership through the complete pointer session and a shared on-demand display clock only while visible progress needs repainting.

Research asset: [Zen sidebar media cards](../../../docs/research/zen-sidebar-media-cards.md).
