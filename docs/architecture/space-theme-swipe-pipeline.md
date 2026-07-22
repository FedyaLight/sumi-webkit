# Space Theme Swipe Pipeline

This is the intended ownership model for workspace switching and workspace-theme updates.

## Owners

- `SidebarSwipeCaptureSurface.swift`
Captures horizontal scroll/swipe events at the sidebar edge.
- `SpaceSwipeGestureTracker.swift`
Normalizes live swipe progress before sidebar transition state updates.
- `SpacesSideBarView.swift`
Translates swipe events into window-local interactive workspace transitions.
- `WorkspaceThemeCoordinator.swift`
Owns committed theme, interactive preview theme, and transition progress.
- `BrowserManager.setActiveSpace(...)`
Commits the selected workspace and tab. It does not synthesize late theme previews.
- `SpaceSidebarTransitionCoordinator`
Stores the latest logical scroll viewport for every space. The same viewport is
used by transition snapshots and by the next committed interactive scroll view.
- `SidebarSelectedItemRevealOwner`
Queues the latest reveal path until its interactive scroll surface is ready,
then publishes repeatable selection and selected-row-hover reveal intents.
- `SidebarSelectedItemVisibilityScope`
Owns the surface's initial `ScrollPosition` and resolves reveal intents through
one `ScrollViewProxy`. Its scroll-geometry receipt separates viewport restoration
from the first reveal animation. Selection callers never issue scroll commands.

## Rules

- Live swipe preview must begin from gesture progress, not from final space selection.
- After emitting `began`, the swipe tracker owns every sample through `ended` or
  `cancelled`; tab-list scroll routing must not reset an active swipe session.
- Phase-less scroll input is one thresholded discrete switch, followed by a
  drained inertial tail; the tail never drives transition progress or another switch.
- Temporarily disabling new swipe capture must not abandon an already-owned
  input sequence. Ownership ends only at that sequence's terminal sample.
- Committing the selected space must not create a second theme transition.
- Browser chrome reads `ResolvedThemeContext`; it should not depend on workspace-specific `colorScheme` injection.
- Global `System / Light / Dark` appearance remains independent from workspace color styling.
- A committed space freezes the viewport intent used by its transition snapshot:
  automatic, top, bottom, or a concrete point. Non-top surfaces mount at the top
  first so nested lazy stacks can publish their real document height; only then
  does the visibility scope restore the saved bottom/point and accept viewport
  updates from the new surface. This prevents an incomplete lazy document from
  overwriting the saved viewport or being left at an impossible nonzero offset.
- Once real scroll geometry confirms restoration, the visibility scope releases
  the latest selected-row reveal in a later animation transaction. Space return,
  close/unload fallback, and selected-row hover therefore share one identity-based
  reveal operation and one motion policy; only the return path has a restoration
  barrier before it.
- Surface readiness is event-driven. It uses neither a fixed delay nor polling,
  and snapshot-only surfaces never release reveal work.
- Before readiness, the newest selection replaces the older pending path. After
  readiness, close/unload fallback and selected-row hover reveal immediately.
- Every direct `LazyVStack` slot carries a stable `SidebarScrollTargetID`.
  Nested content must not own that identity: SwiftUI cannot materialize an
  off-screen slot from an ID hidden inside the slot's view hierarchy.
- Folder selections resolve to a root-to-leaf reveal path. The reveal owner
  advances only when each direct folder target has appeared, then reveals the
  selected row. Closed folders skip non-rendered descendants and target their
  sticky selected projection.
- Programmatic identity scrolling omits an explicit anchor. SwiftUI moves only
  far enough to expose the row, matching Zen's nearest-edge behavior, and uses
  the shared smooth reveal animation.
- Regular tabs, launchers, split groups, collapsed-folder sticky projections,
  and live-folder results all expose a stable scroll identity. Split members
  resolve to the one visible split-group row.
- Hovering a partially clipped selected row issues a fresh reveal generation;
  the scroll view moves only far enough to expose the full row.
- Reduced-motion mode performs the same visibility correction immediately.

## Anti-patterns to avoid

- Synthesizing an interactive theme transition only after the space selection already changed.
- Injecting a discrete workspace `colorScheme` into the whole chrome tree.
- Mixing multiple swipe progress sources without a single normalization step.
- Letting page-derived colors participate in workspace chrome theme selection.
- Calling `ScrollViewProxy.scrollTo` from individual selection sites instead of
  the scroll-surface scope. It loses repeatable hover requests and fragments
  motion policy.
- Depending on an AppKit anchor embedded only in the selected row. Lazy stacks
  do not create an off-screen selected row, so there is no view to register and
  fallback focus silently stalls.
- Restoring scroll position only in transition snapshots while mounting the
  committed interactive `NSScrollView` at its default origin.
- Starting the initial selected-row reveal from `task`/`onAppear` in the same
  mount transaction as viewport restoration. SwiftUI can coalesce both positions
  before a frame is presented, turning a smooth reveal into an instant jump.
- Delaying reveal by a guessed duration. Readiness must come from actual scroll
  geometry so it remains correct across layout cost, hardware, and nested lists.
