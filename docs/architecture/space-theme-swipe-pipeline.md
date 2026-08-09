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
Queues the latest semantic target until its interactive scroll surface and the
unified list presentation are both ready, then publishes one exact reveal.
- `SidebarSelectedItemVisibilityScope`
Owns the surface's mount `ScrollPosition` and every programmatic scroll command.
Its first usable geometry applies viewport restoration without animation; a
geometry receipt proves the result, and a display-pass receipt keeps the first
reveal animation out of the committed page's mount transaction.
- `SidebarListSurface`
Publishes semantic target bounds from the same ordered presentation extents that
render the unified list. It withholds settled geometry during structural reflow.

## Rules

- Live swipe preview must begin from gesture progress, not from final space selection.
- After emitting `began`, the swipe tracker owns every sample through `ended` or
  `cancelled`; tab-list scroll routing must not reset an active swipe session.
- Phase-less scroll input is one thresholded discrete switch, followed by a
  drained inertial tail; the tail never drives transition progress or another
  switch. Because those drivers publish no terminal phase, a quiet interval
  between AppKit event timestamps starts the next sequence without a timer.
- Temporarily disabling new swipe capture must not abandon an already-owned
  input sequence. Ownership ends only at that sequence's terminal sample.
- Committing the selected space must not create a second theme transition.
- Browser chrome reads `ResolvedThemeContext`; it should not depend on workspace-specific `colorScheme` injection.
- Global `System / Light / Dark` appearance remains independent from workspace color styling.
- Theme picker preview and runtime switching use `WorkspaceThemeCoordinator`;
  `ChromeThemeTokens` resolves the concrete colors consumed by browser chrome.
- A window-local Space creation draft previews through the same coordinator
  without entering the Space catalog. Commit preserves its reserved identity;
  cancel restores the source Space theme.
- A committed space freezes the viewport intent used by its transition snapshot:
  automatic, top, bottom, or a concrete point. The real surface starts without a
  pending non-top scroll command; its first usable geometry applies that intent
  in an animation-disabled transaction before the surface can become ready.
  Point restoration clamps to the current reachable extent and bottom restoration
  uses the current bottom.
- Scroll geometry confirms restoration, but does not by itself make the surface
  ready. The first AppKit display pass of the interactive committed surface is
  the presentation barrier; only its receipt releases the reveal in a separate
  SwiftUI animation transaction.
- Surface readiness is event-driven. It uses neither a fixed delay nor polling,
  and snapshot-only surfaces never release reveal work.
- Before readiness, the newest selection replaces the older pending target. After
  readiness, close/unload fallback and selected-row hover reveal immediately.
- Every selectable unified-list element maps to one stable semantic
  `SidebarScrollTargetID`. Its target bounds come from ordered presentation
  extents, so nested-folder rows do not need lazy identity materialization.
- Programmatic scrolling preserves nearest-edge behavior. A revealed row reserves
  one complete `SidebarRowLayout.rowGap` (4pt) against either viewport edge when
  the surrounding content makes that gap reachable. One shared smooth animation
  owns the final offset, with no delayed correction.
- Regular tabs, launchers, split groups, collapsed-folder sticky projections,
  and live-folder results all expose a stable semantic target ID. Split members
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
- Delaying reveal by a guessed duration. Readiness must come from restored scroll
  geometry plus the committed surface's actual display pass.
- Scheduling a second offset adjustment after the reveal command. It races manual
  scrolling and layout changes; one reveal must own the final destination.
