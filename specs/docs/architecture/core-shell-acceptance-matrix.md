# Core shell acceptance matrix

This is the acceptance baseline for the first complete Aura shell rewrite.

## Spaces and profiles

- switching spaces does not open a second browser window
- each space routes to its bound Chromium profile
- returning to a space restores its previous tab selection
- switching spaces does not corrupt split, glance, or theme state
- switching spaces warms the destination selection when the runtime can do so
- theme transition starts during the switch instead of after commit
- opening a tab from an external app while space routing is enabled never
  freezes the shell or leaves the target space half-switched
- spaces can be renamed and assigned an explicit icon
- if a space has no explicit icon, it falls back cleanly to the first visible
  character or emoji derived from the space name, matching Zen's user-facing
  behavior
- clicking the active space header toggles that space's pinned section
- pinned-section collapsed state restores per space for the current window

## Window modes

- a blank window opens without standard shell tree state
- a blank window does not silently inherit the last standard window shell state
- restore preserves whether a window was `standard` or `blank`

## Folders and reorder

- tabs and launchers can be reordered across multiple nested folder levels
- moving an item never leaves empty gaps or ghost placeholders
- dragging into and out of folders is stable after restore
- folder hover-open and auto-space-switch behavior are deterministic
- collapsed folders keep selected or projected children visible without leaking
  placeholder tabs into runtime ids
- folder reset clears all active-folder projections
- nested subfolders stop at depth `5`
- folder row density matches tab row density

## Sidebar density and surfaces

- collapsed sidebar uses the frozen compact geometry
- essentials, pinned rows, tree rows, footer, and media stack keep stable
  spacing across restore and compact mode
- no dead gaps appear when hover-only affordances are hidden
- no jitter appears when media cards are added, removed, or dismissed

## Essentials

- same-profile space switches keep Essentials visually fixed at the top of the
  sidebar
- switching to a different profile commits to that profile's Essentials strip
- live swipe between different-profile spaces keeps Essentials moving with the
  page during the gesture
- opening an essential creates or reuses a live instance
- a live essential stays attached to its original profile until closed
- relaunch after close uses the current active space profile
- tabs and Essentials require explicit drag slop so simple clicks do not start
  accidental drag or tear-off behavior
- Essentials ordering survives reopen and restore without slot jumbling
- dragging an essential into a split never destroys the global launcher
- an unpinned split created from an Essential-backed live instance keeps the
  Essentials slot reserved as a split-proxy redirect
- clicking that split proxy switches to the owning space if needed and focuses
  the live split group instead of opening a duplicate instance
- pinning that split immediately restores the normal Essentials launcher and
  detaches the split into an independent pinned entity
- unpinning a previously detached split leaves it as a regular split entity and
  never relinks it to the Essentials launcher
- Essentials never show the changed-url launcher slash or reset-icon affordance
  that Zen reserves for changed pinned launchers

## Launchers

- when a pinned launcher-backed live tab leaves its stored launcher URL, the
  row shows the changed-url affordance instead of losing launcher identity
- changed pinned launchers show a slash marker before the live page title
- changed pinned launchers repurpose the icon into a reset button that returns
  to the stored launcher URL
- activating that reset button selects the launcher tab if needed
- `Ctrl` or `Cmd` on the reset action duplicates the changed live page into a
  regular background tab before resetting the launcher
- launcher changed-url state survives temporary split or folder grouping and
  reappears when the launcher returns to normal row presentation
- launcher context menus expose `Edit Icon` with emoji or SVG support
- launcher context menus expose `Replace Launcher URL with Current` for changed
  pinned launchers
- launcher context menus expose `Edit Link` as an Aura-owned extension for
  launcher-backed rows
- launcher icon overrides persist through customization export and import

## Split

- split can be created by drag, menu, or glance promotion
- `Split Tabs` toggles to `Un-split Tabs` when a selected tab is already in a
  split
- `Split Link in New Tab` appears only for real links and never for `mailto:`
  or `tel:` targets
- drag-on-tab dwell matches Zen's `300ms` affordance timing
- tabs can be inserted into an existing split on all valid sides
- split insertion preserves Zen's tree semantics when inserting into an
  existing split
- split layout presets support `grid`, `vertical`, and `horizontal`
- split never shows more than `4` visible members
- dropping a split item on itself at a valid side enters the empty split
  replacement path instead of silently no-oping
- split hover headers expose `rearrange` and `unsplit`
- active split content shows the frozen active outline
- pressing `Escape` while split preview is active clears all preview residue,
  highlights, and temporary targets immediately
- pinning or unpinning any split member propagates to the whole split group
- splitting pinned, essential, and live-folder-backed tabs follows the frozen
  Zen duplication rules
- split groups created from folder tabs keep folder parent linkage
- split groups render in the sidebar as one grouped non-collapsible unit
- moving one split member across spaces moves the whole split group
- split DnD support beyond regular tab-on-tab cases does not silently widen
  itself beyond the frozen Aura rules for Essentials, glance children, and
  live-folder-backed tabs
- unsplitting behaves exactly per the frozen focus rules
- fullscreen hides split chrome without corrupting split layout
- persisted split restore uses `layoutTree` as the canonical structure and
  rebuilds any flat projected split items from it
- restart restores valid split layout trees and collapses invalid ones cleanly

## Profile-bound spaces

- switching to an empty profile-bound space activates the space shell without
  forcing profile runtime startup
- a profile-backed space loads only when real runtime-backed content is needed
- a hidden loaded profile-backed space never creates a second browser window or
  a second browser shell
- if a hidden profile-backed space has no live tabs, live essential instance,
  media, or transfer activity, it is eligible to return to dormant state

## Glance

- glance opens only for eligible links
- `Open Link in Glance` appears only for standard links and never for `mailto:`
  or `tel:` links
- glance remains visible regardless of workspace filtering
- glance is visibly linked to its parent tab
- selecting the parent of a live glance re-selects the live glance child
- switching away from a live glance closes only the visible overlay and keeps
  the parent-child linkage alive
- returning to the parent or live child reopens the glance path deterministically
- next and previous tab traversal from a live glance follow parent-adjacent
  ordering
- glance is not counted as an independent sidebar, pinned, or essentials item
- live glance on a collapsed or Essential-backed row remains a parent-linked
  nested affordance, not a standalone sidebar entry
- glance can expand to a full tab
- expanding a glance places it immediately to the right of its parent
- expanding from a pinned parent inserts it as the first normal visible tab
- expanding from an Essential-backed parent creates a normal regular tab that
  is not pinned and not placed inside the Essentials container
- glance can become a split item
- splitting a glance uses only the parent plus glance pair and disables when the
  active split is already full
- expanding a glance out of split removes glance-only state without corrupting
  the existing split group
- focused glance close uses an explicit confirmation window before commit
- closing glance restores focus deterministically
- moving a parent tab with a live glance to another space moves the live glance
  child to the same space

## Menus and chrome

- sidebar, tab, split, and media menus match the frozen menu matrix
- glance uses the frozen overlay command surface instead of an invented
  separate context menu
- address bar uses one canonical implementation
- unified hub owns site controls and extension pinning
- unified site-controls and unified extensions render as one canonical surface,
  not two adjacent popovers
- theme editor follows the same state model as the rest of the shell
- single-sidebar extension overflow renders below the address bar instead of
  silently moving into the hub
- menus and panels follow the frozen surface taxonomy and anchor rules
- unified hub, theme editor, Ctrl+Tab, and sidebar menus stay bounded and do
  not drift or clip
- app menu and tall panels constrain to available screen height
- Ctrl+Tab panel is transient and never restores after restart

## Address bar and compact mode

- opening a new tab focuses the address bar instead of creating a blank tab
- `Ctrl` or `Cmd` + `T` closes the address bar if it is already open
- blurring the window does not close the address bar
- floating and new-tab URL bar popovers stay anchored to the canonical address
  bar cluster and never render misplaced
- text in the address bar remains selectable and editable in both normal and
  floating paths
- typing a space name can switch spaces directly from the address bar
- typing an extension name can open that extension directly from the address
  bar
- direct URL entry still offers explicit search fallback
- prefixed URL bar actions show all actions and do not train the learner
- the grounded Zen shell-command catalog remains available without a second
  command-bar implementation
- current-tab and current-URL matches receive the frozen Zen-style ranking boost
  ahead of weaker generic matches
- copy-link is disabled for non-`http(s)` pages
- empty-space and floating URL-bar presentation both suppress the site-controls
  anchor deterministically
- compact mode reveal and hide stay stable during drag, split, and fullscreen
- compact mode never leaves the address bar visually stuck afloat
- compact width matches the grounded Zen invariants on left, right, and hover
  reveal paths
- snapped or tiled window geometry does not suppress compact-mode sidebar reveal
- single-toolbar compact mode exposes only the legal `hide sidebar` path

## Keyboard semantics

- default macOS numbered space shortcuts are prefilled for new profiles
- sequential numbering counts essentials first, then pinned items, then regular
  tabs
- wrap-around workspace navigation defaults to `true`
- closing the last unpinned tab does not open a new tab by default
- MRU tab traversal never crosses the current space boundary
- page history shortcuts are never misrouted into space switching
- `Alt` + number never triggers split unless the user explicitly binds it
- Ctrl+Tab traversal stays scoped to the current shell ordering even when
  started from an Essential
- extension keyboard shortcuts keep routing correctly when the sidebar is
  collapsed or compact

## Media

- one background media card per active background session
- muted-but-playing sessions still render cards
- controls route to the same upstream media runtime Helium already owns
- media cards are ordered by most recently active background session
- audible playing sessions show the media-card notes animation
- muted or paused sessions do not show the media-card notes animation
- overflowing media titles only marquee on hover
- dismissing a media card hides it for the current playback epoch only
- focusing a media card switches to the owning space when needed
- media-sharing cards swap playback controls for device controls
- picture-in-picture or fullscreen sessions suppress the standard media card
  path

## Customization settings

- `aura://settings/` exposes `Theme`, `Layout`, `Spaces & Essentials`,
  `Keyboard`, and `Import/Export`
- export includes Aura shell customization only
- import uses replace-current semantics after explicit confirmation
- invalid customization bundles fail without partial apply

## Performance and architecture

- there is one interaction engine, not one drag system per surface
- there is no second media, extension, or tab runtime
- no polling-driven state propagation is introduced for shell behavior
- no synthetic empty tab leaks into runtime tab or restore logic
- no post-commit correction jumps happen after drag, split, or glance actions
- compact mode hover and reveal logic stays centralized and measurable
- folder and icon animations do not introduce new leak-prone observer graphs
- space-switch, theme, and media updates all route through one coordinated
  shell transaction instead of unrelated view-local effects

## Explicit non-goals

- onboarding flow
- settings IA beyond Aura-owned sections and customization import/export
- release packaging polish
- multi-window sync behavior
- live folders as a shipped feature in the first shell rewrite
