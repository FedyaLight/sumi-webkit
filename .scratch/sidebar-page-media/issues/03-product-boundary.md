Type: grilling
Status: resolved
Blocked by: 01, 02

# What product boundary should the Sidebar Page Media effort target?

## Question

Which media sources, capabilities, paused-session behavior, visual model, dismissal behavior, overlay geometry, animations, and private-API constraints define the destination?

## Answer

The player controls only Page Media Sessions owned by Sumi. WebKit is the exact page-scoped authority; MediaRemote is optional enrichment. Only capabilities reported through a native, target-safe path are exposed. Private API is allowed.

A session explicitly paused through the Mini Player remains eligible until exact invalidation. The UI follows Zen: newest card in front, collapsed front card plus up to two peeks reserve fixed footer height, expanded cards overlay upward without changing the tab viewport, and no geometry animation is used. Three cards are materialized; additional active sessions remain lightweight. `×` pauses and dismisses only that session, which may return on a later playback-start event. The card owns every pointer event from press through release so underlying tabs cannot activate.
