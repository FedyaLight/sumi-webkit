Type: prototype
Status: resolved
Blocked by: 02, 03

# Does the Zen-shaped overlay preserve Sumi sidebar interaction ownership?

## Question

Build the smallest local prototype needed to validate a three-card newest-front stack in Sumi: collapsed front card plus two peeks reserve fixed footer height; expansion is immediate and overlays upward without changing the tab viewport; only three card views materialize; `×` is present; card/control presses never reach underlying tabs, including release after card dismissal or reordering; transparent gaps retain their intended behavior. Which SwiftUI/AppKit ownership seam achieves this without broad event monitors, continuous mouse tracking, layout thrash, or extra work while disabled?

## Comments

- This is a disposable HITL prototype and interaction test, not production implementation.
- Compare at least the existing `sidebarAppKitPrimaryAction` routing seam and a dedicated overlay interaction owner; report tradeoffs before choosing.

## Answer

The existing `sidebarAppKitPrimaryAction` seam is sufficient and cheaper than another event owner: it already gives a source-qualified pointer session from press through release. Cards and controls use higher routing priorities than tab rows. Transparent inter-card gaps remain pass-through, while every visible card rectangle is owned by its card.

The shipped local implementation reserves only `40 + 8 × peekCount` points, materializes at most three stable-identity card views, and expands an overlay upward to `76 × cardCount + 6 × gaps` without changing footer or tab-list layout. There are no transitions or geometry animations.
