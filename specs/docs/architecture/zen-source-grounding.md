# Zen source grounding

This document separates three categories of knowledge about Zen:

- hard facts grounded in source or release notes
- strong behavioral inferences grounded in repeated public fixes
- unknowns that must stay explicitly unspecified until a source or live build
  proves them

Aura implementation should treat this document as a guardrail against "close
enough" re-interpretation.

## Why this exists

Zen is the primary UX reference for Aura, but not every Zen detail is available
as a clean, enumerable source of truth. Some values are explicit. Some are
runtime-computed. Some are inherited from upstream Firefox. Some are only
observable through repeated release-note bugfixes.

The implementation rule is:

- if a detail is source-grounded, we may encode it
- if a detail is behavior-grounded but not pixel-grounded, we freeze the
  behavior and keep the geometry flexible
- if a detail is not grounded, we leave it unspecified and avoid hard-coding a
  fake answer

## Hard facts worth carrying into Aura

### Global chrome tokens

These Zen defaults are concrete enough to be used as early visual grounding for
Aura where Helium-native constraints allow it:

- default border radius: `7px`
- toolbar button border radius: `6px`
- context menu border radius: `8px`
- default primary color seed: `#ffb787`
- branding dark: `#1d1d1d`
- branding coral: `#f76f53`
- branding paper: `#ebebeb`
- elevated shadow blur token: `9.73px`

These are grounding values, not a command to clone Zen CSS verbatim into
Helium.

### Vertical tab shell facts

- collapsed tab min-width: `48px`
- collapsed toolbox padding: `6px`
- collapsed toolbox width computes to `60px`
- essentials min tab height: `44px`
- vertical tab block margin: `2px`
- close and reset affordances are hover-revealed, not always visible
- several tab-side affordances use fast `0.15s` fade or transform transitions

### Toolbar facts

- toolbar button visual size is driven by a variable with a `16px` fallback
  icon size

### Theme, workspace, and media facts

- Zen shipped automatic dark/light detection based on browser background
- Zen shipped improved gradient rendering to reduce dithering artifacts
- Zen shipped smoother workspace swiping with animated background transitions
  and improved responsiveness
- Zen shipped monochrome themes and color algorithm customization in its theme
  picker
- Zen's live theme picker includes explicit `auto/light/dark` scheme buttons,
  but they drive the global `zen.view.window.scheme` pref rather than saved
  per-workspace theme state
- Zen's live theme picker also includes preset palette pages, opacity,
  texture, and a `3` color-point cap
- Zen's theme picker uses a `380px` bounded panel with `10px` padding, a
  near-square gradient field, `30px` scheme/action buttons, and `28px` page
  buttons
- Zen's theme picker positions the scheme row `15px` from the top of the
  gradient field, uses `5px` gaps between overlay controls, and renders preset
  swatches as `26px` circular chips with hover/press scaling
- Zen's primary draggable color point is `38px` with a `6px` white border, and
  regular color points use the standard medium icon size with a `3px` border
- Zen's macOS theme picker clamps opacity to `0.30..0.90`
- Zen's texture control snaps to `16` positions around a circular ring
- Zen's texture ring uses a `5rem` wrapper by default, `6rem` on macOS, `4px`
  ring dots, and a `6px` handler that grows taller on hover
- Zen exposes URL-bar-adjacent prefs for copy-link, PiP visibility, and
  contextual identity visibility
- Zen exposes an acrylic-elements preference and a `dark-mode-bias` preference
- Zen's media-controller-style UI already handles multiple simultaneous media
  sources
- a Zen-like animated audio indicator on media cards is a required Aura parity
  behavior, but its exact visual cadence is not source-grounded in the public
  materials we have
- Zen's Glance default keyboard shortcut for `expand to full tab` is
  `Accel+O`
- Zen's Glance close confirmation window is `3000ms`
- Zen's Glance parent background scales to `0.97` while open
- Zen's Glance overlay control cluster is ordered:
  - `Close`
  - `Expand`
  - `Split`
- Zen's Glance overlay control cluster uses:
  - `top: 15px`
  - `padding: 12px`
  - `gap: 12px`
  - `max-width: 56px`
- Zen's URL bar learner stores bounded per-command scores in the range `-5..5`
- Zen's workspace navigation defaults to wrap-around enabled
- Zen defaults `open new tab if last unpinned tab closes` to `false`
- Zen caps nested subfolders at depth `5`
- Zen folder icons live inside the folder shell SVG itself, not as separate
  trailing badges
- Zen folder icons can be replaced through `Change Folder Icon`, and active
  collapsed folders swap the custom icon for the internal dots state
- Zen workspace icons can be explicitly set through the same emoji or SVG
  picker family, and when absent they fall back to the first visible character
  or emoji from the workspace name
- Zen launcher-backed rows can also override their icon through that emoji or
  SVG picker family
- Zen's changed-url launcher affordance applies to pinned launcher-backed tabs
  only, not to Essentials
- when a pinned launcher-backed tab changes URL, Zen shows a slash-style
  separator before the live title and repurposes the icon area into a
  reset-to-launcher button
- `Accel` on that reset action duplicates the changed live page into a regular
  unpinned tab before resetting the pinned launcher
- Zen preserves the changed-url launcher state across temporary split or folder
  grouping through the hidden `had-zen-pinned-changed` carry state
- Zen exposes `Replace Pinned URL with Current`, `Edit Title`, and `Edit Icon`
  on launcher-backed rows, but a generic `Edit Link` row is not source-grounded

### Menu and panel facts

- Zen's theme picker panel width is `380px`
- Zen uses `10px` arrow-panel radius on macOS and `12px` on macOS Tahoe
- Zen uses `5px` arrow-panel menu-item radius
- Zen uses `2px 0` panel-body padding for popup subviews
- Zen uses `8px` block and `14px` inline panel-row padding
- Zen uses `20px` block and `15px` inline footer-button padding
- Zen uses `8px` permission-section block padding, `16px` inline padding, and
  `4px` permission-row block padding
- Zen constrains tall panels to available screen height instead of silently
  clipping them
- Zen's native macOS popup strategy explicitly distinguishes native and
  `nonnativepopover` surfaces and uses `hidepopovertail` where needed
- Zen's native macOS arrow popovers force transparent background, transparent
  border, zero CSS shadow margin, and rely on OS-provided shadow/material
- Zen's non-native macOS popovers intentionally fall back to menu-like
  appearance and `Menu` background instead of faking native popovers
- Zen's site-controls panel header order is:
  - `Share`
  - `Reader Mode`
  - `Screenshot`
  - `Bookmark`
- Zen's site-controls add-ons section overflows only after `420px`
- Zen's `Copy URL` affordance is enabled only when the active URI scheme
  starts with `http`
- Zen's site-controls security footer uses explicit `secure`, `not-secure`,
  and `extension` identity states
- Zen's `Open Link in Glance` context action appears only for link targets and
  is hidden for `mailto:` and `tel:` links

### Glance behavior facts

- Zen Glance opens only for `http`, `https`, or `file` URLs
- selecting the parent of a live glance reselects the live glance child
- next or previous tab traversal from a glance uses parent-adjacent ordering
- Glance is always visible regardless of workspace filtering
- expanding a glance moves it immediately after the parent
- when the parent is pinned, the expanded glance becomes the first normal
  visible tab
- Glance split is not arbitrary insertion:
  - Zen fully opens the glance first
  - then splits only the `parent + glance` pair
  - and reverses the pair order when the sidebar is on the right
- Zen disables `Split Glance` when the current split is already full
- Zen excludes live glance children from normal tab, pinned, and Essentials
  counting paths
- Zen preserves live glance linkage when switching away and back through the
  parent row
- Zen renders the live glance child as a nested parent-row affordance instead
  of a standalone sidebar row
- when Glance is expanded from an Essential-backed parent, the promoted tab is
  not pinned and is not kept inside the Essentials container

### Split view facts

- Zen caps visible split members at `4`
- Zen exposes explicit split commands for:
  - `grid`
  - `vertical`
  - `horizontal`
  - `unsplit`
  - `Split Link in New Tab`
  - `New Empty Split`
- Zen injects `Split Tabs` immediately before the host `Move Tab To Split View`
  tab-context row
- Zen's tab-on-tab split affordance uses a `300ms` dwell path
- Zen's DnD workspace auto-switch delay defaults to `1000ms`
- Zen shows a hover header on active split content with:
  - `rearrange`
  - `unsplit`
- Zen persists a split `layoutTree`, not just a flat item list
- Zen propagates pin and unpin operations across the whole split group
- Zen preserves folder parent linkage when a split is created from folder tabs
- Zen duplicates pinned, essential, and live-folder-backed tabs before split in
  specific cases instead of consuming the original launcher-backed tabs
- Zen's drag-over-split path is intentionally narrower than command split and
  rejects Essentials, live glance child tabs, existing split groups,
  live-folder-backed tabs, and multi-select drags
- Zen renders split groups in the sidebar as non-collapsible grouped units
- Zen moves a split group across spaces as one grouped unit

### Icon facts

- Zen's icon registry is centralized in `icons.css`
- Zen ships concrete mirrored assets for the first-pass surfaces Aura needs:
  - theme picker
  - site controls
  - permission rows
  - workspace/folder menus
  - media controls
  - panel headers
- Aura now keeps a local mirrored reference copy under:
  - `/Users/fedaefimov/Downloads/Aura/Aura/aura/resources/icons/zen-reference/zen-icons`

## Strong behavioral grounding

These are not complete pixel specs, but they are strong enough to freeze Aura
behavior:

- repeated fixes around compact mode mean reveal and hide must be centralized,
  measurable, and cheap
- repeated fixes around split and drag mean preview and commit must stay
  separated and id-based
- repeated fixes around glance mean modifier interactions must be explicit and
  regression-tested
- repeated fixes around URL bar mean command routing, reopen/close, and blur
  behavior are part of core shell logic, not incidental view behavior
- repeated fixes around pinned tabs and spaces mean restore and routing must be
  model-driven, not view-heuristic
- repeated fixes and tests around folders and split duplication mean Aura must
  preserve the same user-visible split/pin/folder propagation rules even while
  using cleaner internals than Zen

## Explicitly unspecified values

Until a grounded source or live implementation proves otherwise, Aura must
avoid freezing:

- a pixel-perfect expanded sidebar width
- exact toolbar and URL bar heights on every platform
- exact resolved colors for formula-driven Zen theme values
- complete keyboard shortcut defaults beyond source-grounded cases
- pixel-perfect Ctrl+Tab panel metrics
- Theme Store and Mods page visual geometry
- exact cadence of the media note animation

When these are needed, the implementation should:

1. point to the missing source
2. choose a temporary Aura value
3. mark it as a downstream default, not "what Zen does"

## Implementation policy

- do not encode guessed geometry as if it were canonical Zen behavior
- do not copy Firefox or Zen internals wholesale just to obtain a visual value
- do use hard facts to seed Aura defaults where they improve parity cheaply
- do keep Helium-native ergonomics and performance in mind when translating Zen
  values to Chromium Views
- do prefer formulas, constraints, and behavior rules over fake precision
