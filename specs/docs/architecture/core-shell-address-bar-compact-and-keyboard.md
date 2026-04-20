# Core shell address bar, compact mode, and keyboard semantics

This document freezes the three interaction areas that remained under-specified
after the first core shell spec pass:

- canonical address bar behavior
- compact mode reveal and hide behavior
- keyboard semantics for spaces, tabs, split, and command routing

Zen's user manual and release notes are the canonical reference. Aura keeps the
same interaction model except where Essentials deliberately diverge.

## Canonical address bar model

Aura has one address bar implementation with three presentations:

- attached
- floating
- compact-reveal

The presentation is a view concern only. Search, command routing, extension
results, space switching, and focus return rules are shared across all three.

Aura also keeps a separate URL bar learner path:

- learner state is local adaptive history, not import/exportable customization
- learner state is not part of window restore
- prefixed action mode bypasses learner training

## Address bar open and close rules

- opening a new tab uses the address bar instead of creating a blank tab first
- `Ctrl` or `Cmd` + `T` opens the address bar in `new-tab replacement` mode
- if the address bar is already open, pressing `Ctrl` or `Cmd` + `T` again
  closes it
- `Ctrl` or `Cmd` + `L` always focuses the canonical address bar
- `Esc` closes the address bar and returns focus to the previously focused
  surface
- window blur does not close the address bar by itself
- typed query text is remembered across close and reopen until a successful
  navigation, explicit clear, or refresh invalidates it
- address bar state is transient window runtime state, not durable restore

## Address bar result ordering

When the address bar is focused, Aura should rank results in this order:

1. explicit command bar actions
2. extension actions matched by name
3. space-switch results matched by name
4. direct navigation results
5. search results

Additional Zen-derived rules:

- pressing `Tab` on an empty command-focused address bar shows all available
  commands
- prefixed action mode shows all available actions even if the typed query is
  still short
- prefixed action mode never trains the learner
- command results must stay available regardless of UI language
- when the user types a direct URL or bare domain, Aura shows both:
  - direct navigation
  - explicit "search for this text" fallback
- typing an extension name may open that extension action directly
- typing a space name may switch spaces directly
- `Copy Current URL` is enabled only for `http` and `https` pages
- the grounded shell-command catalog includes compact mode, theme picker,
  split, folder, settings, window, tab, screenshot, Essentials, extension, and
  appearance actions taken from Zen's live global action set
- command matching uses both visible labels and alias terms so that actions
  remain discoverable by user phrasing rather than only exact labels
- current URL matches receive an explicit ranking boost for `Copy Current URL`
- page-backed tab actions receive a live-page context boost over weaker generic
  commands when a real tab is active

## Address bar presentation rules

- in standard browsing mode, direct click focus uses the attached presentation
- in new-tab replacement flow, focus uses the floating presentation unless the
  user explicitly disables it in settings
- compact mode may temporarily reveal the same address bar in
  `compact-reveal` presentation, but the logic stays identical
- floating presentation selects the full untrimmed URL value instead of the
  user-facing trimmed display value
- in single-sidebar layout, overflowing extension actions render below the
  address bar instead of being pushed back into the site controls hub
- the site controls hub remains a stable trailing affordance and must not
  silently absorb overflow extension actions during normal single-sidebar use
- site-controls anchor visibility is suppressed while the shell is in
  empty-space or floating/breakout presentation

## Compact mode model

Compact mode is a window-scoped shell state, not an ad hoc view effect.

In the first single-toolbar Aura rewrite, the only legal exposed compact path
is `hide sidebar`. The content host must never own compact mode state.

## Compact mode reveal behavior

- hidden chrome is revealed only by entering the correct edge hover zone or by
  explicit keyboard toggle
- reveal does not trigger from incidental pointer movement inside page content
- hover reveal stays open while the pointer remains in the revealed chrome
- after hover exit, compact chrome auto-hides after the configured delay
- default auto-hide delay is `1000ms`
- opening a new tab may temporarily flash the compact chrome if that preference
  is enabled
- default temporary flash duration is `800ms`
- while a drag session is active, compact reveal stays open for the active
  valid drop zone until the drag commits or cancels

## Compact mode anti-regression rules

- the address bar must not remain visually "stuck afloat" after compact reveal
  hides
- compact mode must not create empty top-button gaps when the top button row is
  empty
- split UI must stay coherent in collapsed or compact states
- fullscreen hides compact chrome borders cleanly
- workspace theme transitions in compact mode must animate with the space
  switch instead of snapping afterward
- hover and reveal implementation must use one event-driven controller, not a
  large graph of observers or polling loops

## Keyboard semantics

Keyboard shortcuts are user-customizable, but Aura freezes the action
semantics and fallback behavior.

### Space and sidebar shortcuts

- `switch to next space`
- `switch to previous space`
- `switch to space 1..N`
- default new-profile bindings on macOS mirror Zen's `control + number` space
  switching behavior
- wrap-around workspace navigation defaults to `true`
- space switching shortcuts must never be confused with page history shortcuts

### Address bar and command shortcuts

- `Ctrl` or `Cmd` + `T`: open or close the address bar in new-tab replacement
  mode
- `Ctrl` or `Cmd` + `L`: focus the address bar
- `Esc`: close the address bar and restore previous focus target
- `Tab` on empty command bar: reveal all commands

### Split and glance shortcuts

- split horizontal
- split vertical
- split grid
- un-split all
- promote glance to full tab
- promote glance into split

Split shortcut behavior matches Zen:

- calling a split layout shortcut with no current split creates a split with
  the current tab and the next eligible visible tab
- `shift + un-split` keeps focus on the surviving split item when possible
- the default new-profile binding for `promote glance to full tab` mirrors Zen
  as `Accel + O`

### Tab traversal and numbering

- sequential traversal counts essentials first, then pinned items, then regular
  tabs
- if MRU traversal is enabled, it stays window-scoped and never crosses the
  active space boundary
- closing the last unpinned tab does not open a new tab by default
- numbered tab targeting mirrors Zen:
  - essentials occupy the first numbered slots
  - pinned items come next
  - regular tabs follow

## Pinned and essential interaction details

- clicking the active space header toggles the visibility of the per-space
  pinned section
- activating a resettable pinned launcher selects it if not already selected
- `Ctrl` or `Cmd` while activating a resettable pinned launcher duplicates it
  into the background instead of consuming the pinned launcher state
- a changed pinned launcher shows a slash marker before the live page title and
  repurposes its icon as a reset-to-launcher button
- the changed pinned-launcher affordance never appears on Essentials
- dragging a pinned item out of the window must not implicitly create a new
  window
- external links opened inside essentials follow the Zen-style default glance
  path unless the user explicitly requests a full tab

## Scope limits

This freeze covers shell semantics only. It does not yet define:

- the keyboard shortcut settings UI
- onboarding text
- multi-window sync behavior
