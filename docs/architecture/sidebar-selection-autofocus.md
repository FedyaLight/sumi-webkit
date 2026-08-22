# Sidebar selection autofocus

The sidebar scrolls itself so the selected Sidebar Visual Item is fully visible
after every accepted selection change. This document records the behavior
contract, the defects that led to the current implementation, and the
decisions that shaped the rebuild.

## Selection autofocus contract

Every accepted selection change enters one reveal path. The path delegates the
actual scroll to the platform and keeps the selected item visible with the
smallest possible movement.

```
selection accepted → reveal request
  → if the scroll content overflows:
      scroll the selected item into view
```

Key properties:

1. **One trigger.** Every selection path, including clicks, keyboard cycling,
   close-selects-neighbor, undo close, drag start, and new foreground pages,
   produces one reveal request.
2. **Overflow gate.** The sidebar does not scroll while its content fits the
   viewport.
3. **Nearest-edge minimal displacement.** The scroll uses the nearest edge.
   It never centers or moves a fully visible item.
4. **Platform-owned smoothness.** Smooth scrolling comes from CSS
   `scroll-behavior: smooth` and the sidebar motion policy. Reduced-motion users
   always get instant snapping. There is no hand-rolled easing.
5. **Coalescing and interruption.** A pending request is coalesced so the last
   request for a frame wins. A newer programmatic scroll supersedes an older
   one, and wheel or touch input interrupts programmatic scrolling natively.
6. **No snap on overflow onset.** Content growth, such as folder expansion,
   does not start a second scroll while the selection is already being handled.
7. **Instant variants.** Window resize, fullscreen changes, UI density changes,
   and startup settling use an instant reveal.
8. **Space switch before selection commit.** The space-switch path points the
   selection owner at the destination space's scroll container before committing
   the new selection. Each space keeps its own live scroll container, so its
   scroll offset survives switches without snapshot machinery. Switches are
   serialized, prior switch animations are force-completed, and the scrollbar
   is suppressed across the transition.
9. **Cross-space selection.** Selecting an item in another space switches to
   that space first and remembers each space's last-selected item. Fallback
   selection prefers the remembered item, then the first non-pinned visible
   item, and never selects closing or pending-pinned items.
10. **Background opens do not steal the viewport.** A new background item is
    scrolled into view only when smooth mode is on and it is not fully visible.
    The chosen offset keeps both the new item and the selected item visible.
    Otherwise the new item only gets a short highlight.
11. **No virtualization.** Every item is a real view. There is no lazy-list
    geometry problem to solve.
12. **Selected items are always eligible targets**, even inside collapsed
    containers whose expansion animates separately.

## Current Sumi defects

The existing pipeline is projection → `SidebarSelectedItemVisibilityScope.task(id:)`
→ `SidebarSelectedItemRevealOwner.advancePresentedLayoutReveal()` → a
generation-stamped `Request(destinationY:)` → `.onChange` → one
`withAnimation(.smooth)` call to `scrollPosition.scrollTo(y:)`. Root causes of
"jumps" and dead downward reveals:

1. **Silent permanent drop of pending intent.**
   `advancePresentedLayoutReveal()` (`SidebarSelectedItemVisibility.swift:211`)
   clears `pendingTargets` before computing `destinationY`. If
   `revealOffset(in:)` returns `nil` because the delivered geometry is stale or
   mid-momentum, the request is discarded forever. Nothing retries,
   `.task(id:)` does not refire, and only hovering the selected row recovers.
   Downward reveals are hit hardest because their guard depends on an accurate
   current offset.
2. **Two-phase motion after a space switch.** The committed page mounts at the
   saved offset without animation, then a separately animated reveal moves to
   the selected item. Users see restore-then-move, or an instant jump if
   SwiftUI coalesces both transactions.
3. **Stale geometry at decision time.** Native geometry is deferred by one main
   queue hop (`scheduleGeometryDelivery`,
   `SidebarTabListScrollRegistrationView.swift:223`). The destination is
   computed against `lastDeliveredGeometry`, one frame behind real layout,
   folder expansion, lazy-stack growth, or momentum.
4. **Content-height gate vs lazy-stack estimates.**
   `surfaceGeometry.contentHeight + 1 >= autofocusLayout.contentHeight` compares
   AppKit's document height, which includes unmaterialized-row estimates, with
   settled presentation extents. Underestimation stalls downward reveals while
   overestimation lets `scrollTo(y:)` clamp short of deep targets with no
   correction pass.
5. **Readiness races ahead of final layout.** The display-pass receipt grants
   surface readiness on the first paint, which can precede final document
   layout. Restoration then stops reconciling once ready, so a late-growing
   document is never realigned and the reveal uses stale geometry.
6. **Elastic overscroll feeds raw offsets.**
   `reportCurrentScrollBoundaries` reads the raw clip-view origin without
   clamping. Negative bounce offsets can satisfy or spoil one-point comparisons.
7. **Missing instant variants.** Nothing re-reveals on window resize, fullscreen
   transitions, or density and font changes.

## Target architecture

Keep the seam. Callers still speak in semantic target IDs and push layout and
geometry facts. Rebuild `SidebarSelectedItemRevealOwner` around this contract:

> Reveal intent is never dropped until it has been executed against usable
> native geometry or superseded by newer intent. Visibility is verified after
> execution against fresh geometry. A failed verification re-executes while
> content is still growing, within a bounded budget.

### Interface (unchanged shape, new semantics)

```swift
reveal(_ path)            // latest intent wins; supersedes older pending intent
cancelReveal()
updateAutofocusLayout(_:) // settled extents; nil during structural reflow
updateSurfaceGeometry(_:) // freshest native geometry (clamped)
surfaceDidBecomeReady()   // readiness receipt

// output: Request(targetID:, purpose:, destinationY:, generation:)
```

### Core loop rules

1. **Consume on execute, not on gate.** Remove `pendingTargets.removeAll()`
   before offset computation. A pending target leaves the queue only when a
   scroll command was issued against usable geometry or verification confirms
   that the target is fully visible.
2. **Verify and retry instead of using a one-shot gate.** A short native
   document receives an immediate command to its reachable edge. That command
   can make `LazyVStack` materialize more content. Each later geometry delivery
   checks whether the target is fully visible. Content growth replenishes a
   three-command correction budget. Reachable-offset growth without new
   content consumes that budget. This removes the content-height deadlock and
   prevents resize frames from publishing commands without a bound.
3. **Decide at execution time against fresh geometry.** The registration view
   writes to a shared geometry box synchronously. `destinationY` is computed
   from that box in the same run-loop turn that issues the scroll command. The
   async delivery channel remains for state observation only.
4. **Clamp reported offsets** to `[0, maximumOffset]` before comparisons. This
   removes elastic-bounce artifacts.
5. **One visible reveal after a space switch.** Mount the saved viewport without
   animation. Once the first presented receipt makes the surface ready, issue
   at most one selection reveal. Restoration stops after readiness. Later
   correction belongs to the same verified reveal intent. Sumi rebuilds the
   destination scroll view, so preserving the saved mount position avoids a
   larger restoration rewrite.
6. **Keep the good parts already present.** Do not snap during structural
   animations. Withhold layout until `.logicallyComplete`, queue pending intent
   instead of firing mid-reflow, avoid a snap when content first overflows, and
   use `SidebarMotionPolicy` for reduced-motion behavior. Hovering the selected
   row remains a legitimate secondary trigger, not a workaround.
7. **Keep drag ownership outside the reveal owner.** A pointer activation starts
   on a visible row, so its reveal is a no-op. Hover repeats stay suppressed
   while a pointer or drag session owns the sidebar.

### Scenario matrix

| # | Scenario | Sumi owner | Action |
|---|----------|------------|--------|
| 1 | Pointer activation of a tab, launcher, or split member | Page Activation → projection path → scope `.task` | keep; fix dropped intent and stale geometry |
| 2 | Keyboard cycling or palette activation | same path as #1 | covered by #1 |
| 3 | Close selects neighbor; undo close | selection snapshot change | covered by #1 |
| 4 | New foreground page, including open animation | layout publish at `.logicallyComplete` plus queued intent | keep |
| 5 | New background page | selection unchanged | no reveal and no pulse |
| 6 | Activation inside a collapsed folder | folder-chain targets; expansion runs first and reveal waits for settled layout | keep; verify the chain materializes |
| 7 | Cross-space selection from a palette, link, or command | space switch commits, then #1 in the destination surface | keep |
| 8 | Explicit space switch by click, swipe, or gesture | transition coordinator mounts the seeded viewport, then reveals after readiness | keep the verified one-reveal path |
| 9 | Per-space last-selected memory and fallback pick | per-space selection restore | keep |
| 10 | Window resize or sidebar size change | viewport resize observer | re-run reveal instantly after a size change |
| 11 | Fullscreen enter or exit | viewport resize observer | reveal instantly when the surface size changes |
| 12 | Density or font-size change | no dynamic sidebar density or row-font setting today | a future setting must send an explicit relayout reveal |
| 13 | Startup or session-restore settle | restoration receipt, then one selection reveal | keep one reveal; reduced motion remains instant |
| 14 | Content starts overflowing during folder expansion | no reveal on content growth | keep absent |
| 15 | Drag start selects the dragged item | pressed row is already visible; hover repeats are interaction-gated | no separate owner state |
| 16 | Pin, unpin, container conversion, or split edit | structural animation withhold plus queued intent | keep |
| 17 | Pinned-collapse toggle with sticky projections | sticky projections are excluded from targets; reveal waits through disclosure | keep |
| 18 | Empty Page activation | Empty Page owns a regular row | reveal normally |

## Implementation status

Implemented:

1. **Consume on execute** (`SidebarSelectedItemVisibility.swift`):
   `revealDisposition` distinguishes unusable geometry from a genuinely visible
   target. Only a real verdict consumes pending intent. The silent
   downward-reveal drop is gone.
2. **Fresh geometry at decision time:** the AppKit observer writes every scroll
   report synchronously into `SidebarSurfaceGeometryBox`. The owner pulls it
   through `setGeometryProvider` before deciding instead of trusting the
   coalesced delivery hop.
3. **Progressive verify and retry:** a short native document scrolls to its
   reachable edge immediately instead of waiting behind the old content-height
   gate. An issued command stays verified against fresh geometry. Content growth
   replenishes three reachability corrections. Viewport-only growth consumes
   that budget. Confirmed visibility clears the state so later content changes
   never yank the user back.
4. **Elastic clamp:** reported offsets are clamped to `[0, maximumOffset]`
   before any comparison.
5. **Instant viewport variants** for resize and fullscreen: viewport size
   changes after mount trigger
   `revealLastSelectionWithoutAnimation()`
   (`Request.Purpose.relayoutAdjustment`). Instant semantics survive
   verify-and-retry corrections because they belong to the intent, not one
   issuance.
6. **Drag suppression was dropped as unnecessary:** activation reveals are a
   no-op on a just-pressed visible row, and hover sessions are suppressed while
   a pointer or drag session owns the sidebar.

Space-switch behavior intentionally keeps its mount-at-saved-viewport step,
followed by exactly one animated reveal. With correct targeting that is a single
visible motion, which the existing monotonic-offset tests encode. Removing
viewport restoration would add churn without removing a visible defect.

Regression coverage lives in
`SumiTests/SidebarSelectedItemVisibilityTests.swift` (fresh-provider decisions,
progressive reachability, bounded viewport corrections, satisfaction clearing,
animation purpose, instant relayout purpose, elastic clamp, resize re-reveal)
and the opt-in UI suite
`SumiUITests/SumiSidebarSelectionUITests.swift` (`SUMI_RUN_INTERACTION_E2E=1`)
covers down, up, and pinned autofocus across space switches end to end.
