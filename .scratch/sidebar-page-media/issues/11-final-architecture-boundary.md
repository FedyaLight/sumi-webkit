Type: grilling
Status: resolved
Blocked by: 05, 06, 07, 08, 09, 10

# Which final architecture and rollout boundary should Sumi implement?

## Question

Choose the final module ownership, event flow, state identities, UI projection, command path, optional enrichment boundary, failure/degradation behavior, migration order, and narrow verification matrix that satisfies every resolved decision. Confirm that no unresolved architectural choice, resource workaround, site-specific bypass, or wrong-target path remains before handing the specification to implementation planning.

## Answer

The local implementation now uses a shared event-driven controller that publishes full ordered snapshots of exact WebView-residence cards. Window-local stores hide their selected source and materialize the first three. The Zen-shaped SwiftUI overlay owns presentation only; WebKit owns lifecycle, sampling, and commands. Unsupported transport features are absent and MediaRemote is absent.

Verification covers stale metadata, WebView replacement, multi-residence selection, late command completion, retained pause/resume, dismissal/recreation, ordering, three-card projection, overlay geometry, collapsed-sidebar parity, and the shared AppKit pointer-session regression suites. The app target builds for macOS 15.5.
