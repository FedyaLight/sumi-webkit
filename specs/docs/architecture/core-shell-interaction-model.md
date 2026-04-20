# Core shell interaction model

Zen is the canonical reference for drag-and-drop, reordering, split, glance,
workspace switching, and focus behavior. Aura keeps only the Essentials
divergence defined in `core-shell-overview.md`.

## Interaction engine

Every shell mutation goes through one engine:

1. begin interaction session
2. compute geometry-derived `AuraDropIntent`
3. render preview only
4. commit or cancel

Views do not mutate tree order, split layout, or glance state directly.

## Sidebar tree rules

- each space owns one ordered root entry tree
- root entries may be launchers or folders
- pinned launchers and pinned tabs render in a dedicated per-space pinned
  section above the regular tree, following Zen’s layout
- folders may nest arbitrarily
- essentials are not normal tree entries and cannot be nested into folders
- pinned launchers and pinned tabs cannot be nested into folders

## Drag session lifecycle

- drag origin is always typed:
  - entry node
  - tab
  - essential
  - split item
  - glance preview
- drag preview follows the current intent only; it must not pre-mutate state
- leaving a valid target clears preview but preserves the session
- escape or mouse-up on no target cancels without mutation

## Reordering and folder behavior

- reorder is always before/after a concrete target id
- pinned items reorder only within the pinned section of their current space
- dropping on a folder body creates an `into-folder` intent
- dropping between folder children extracts or inserts by id, never by index
- hovering a collapsed folder with a valid `into-folder` intent for 600ms opens
  the folder preview target
- hovering a space switcher target during drag for 1000ms activates that space so
  the drop can continue there
- folders can contain regular launchers only; essentials remain outside folders
- clicking the active space header toggles the pinned section for that space
- dragging a pinned item out of the window never creates a new window
- resettable pinned launchers select themselves on activation if needed
- `Ctrl` or `Cmd` while activating a resettable pinned launcher duplicates it
  into the background instead of consuming the pinned launcher state
- when a pinned launcher-backed live tab leaves its stored launcher URL:
  - the row enters a changed-url state instead of losing launcher identity
  - a slash marker appears before the live title
  - the launcher icon becomes a reset button that returns the live tab to the
    stored launcher URL
- Essentials never show the changed-url slash or reset-icon affordance, even if
  their live instance navigates away from the original URL
- temporary grouping into split or folder projection must preserve the
  changed-url launcher state instead of silently dropping it

## Essentials behavior

- dragging a regular tab or launcher into the essentials zone creates or
  reorders an essential launcher
- dragging an existing essential reorders essentials only
- an Essential always keeps its slot reserved in the Essentials strip
- dragging or command-splitting an essential uses only its live instance; it
  never consumes the profile-owned launcher
- if a live essential enters split without becoming pinned:
  - the Essentials slot switches to a split-proxy affordance
  - the proxy redirects to the active split group instead of opening a second
    live instance
  - closing the split returns the surviving live instance to the Essentials slot
- if that split group becomes pinned:
  - the Essentials slot immediately restores the normal launcher
  - the split group becomes a standalone pinned entity
  - the former live essential instance is detached from the launcher and must
    not auto-reattach later
- if a detached split group is later unpinned, it remains a regular split
  entity and does not relink itself to the Essentials launcher
- this `Essential -> split by drag` path is an Aura-owned extension because the
  current live Zen drag-over-split implementation still rejects Essentials
- live essentials remain attached to the profile they were opened in until that
  instance closes or unloads

## Launcher editing behavior

- launcher-backed rows keep one persisted launcher URL as their canonical target
- Zen exposes `Replace Pinned URL with Current` for changed pinned launchers
  instead of a generic edit-link row
- Aura keeps that Zen action for changed pinned launchers and adds an explicit
  `Edit Link` action for launcher-backed rows as an Aura-owned extension
- launcher-backed rows support custom icon overrides through the same emoji or
  SVG picker family Zen uses for tabs, folders, and spaces

## Split behavior

- dragging a tab to the edge of the content host exposes split targets
- dragging a tab to the center exposes `split top` and `split bottom`
- dragging a tab on top of another tab for `300ms` exposes the split-on-tab
  affordance, matching Zen's dwell behavior
- split view supports up to 4 simultaneously visible split items
- split presets are explicit:
  - grid
  - vertical
  - horizontal
- split insertion is explicit:
  - left
  - right
  - top
  - bottom
- dropping into an existing split uses the visible edge target
- dropping into an existing split may either:
  - insert into an existing compatible axis node
  - wrap the hovered split node in a new parent when the side changes axis
- split reordering remains tree-based and id-based; Aura must not flatten split
  layout into simple list reindexing
- dropping a split item on itself at a valid split side creates an empty split
  replacement affordance instead of silently doing nothing
- split items expose a hover-only header toolbar in the content area with:
  - `rearrange`
  - `unsplit`
- the active split item shows a visible active outline, following Zen
- `Split Link in New Tab` is a first-class action and routes through the same
  split insertion engine as drag-created splits
- `Split Tabs` in the tab context menu toggles to `Un-split Tabs` when any
  selected tab is already in split
- split context actions are valid only for `2..4` selected tabs and reject
  empty-split placeholder surfaces
- split duplication rules follow Zen exactly:
  - `normal + pinned` duplicates only the pinned-backed side into an unpinned
    split group
  - `pinned + pinned` creates no duplicates and the split group remains pinned
- `pinned + essential` duplicates and preserves both original launcher-backed
    tabs outside the split group
  - `essential + essential` duplicates and never consumes the global
    Essentials-backed launchers
  - live-folder-backed tabs use the same duplication-protection path as pinned
    or essential-backed tabs
- pinning a split group created from an Essential-backed live instance detaches
  that group from the launcher and restores the launcher immediately
- pinning or unpinning any tab inside a split propagates to the whole split
  group
- split groups created from folder tabs preserve folder parent linkage
- unsplitting a tab normally focuses the unsplit tab
- shift-unsplit preserves current focus if the currently focused split item
  survives the operation
- unsplitting the last remaining member removes the split group cleanly
- split restore persists a layout tree and must collapse invalid restored trees
  cleanly instead of reopening a broken split
- fullscreen hides split chrome but does not destroy split layout

## Glance behavior

- `Open Link in Glance` appears only for real links and stays hidden for
  `mailto:` and `tel:` targets
- glance opens only for eligible `http`, `https`, or file links
- glance is always parent-linked to the tab that spawned it
- eligible links opened from pinned and essential contexts default to the same
  glance path unless the user explicitly requests a full tab
- bookmark-triggered glance uses the configured modifier-based activation path
- search-result glance, when enabled, follows the same parent-linked runtime and
  does not create a second glance model
- sidebar renders glance as a compact parent-adjacent affordance, following Zen
- selecting a live glance parent re-selects the live glance child
- next or previous tab traversal from a live glance uses the parent-adjacent
  ordering instead of raw child placement
- expanding a glance creates a full tab in the current space and profile and
  moves it immediately to the right of the parent
- expanding from a pinned parent inserts the new full tab as the first visible
  non-pinned tab
- reducing motion skips the full expand animation path and settles immediately
- splitting a glance is exact:
  - fully open the glance first
  - split only the pair `parent + glance`
  - reverse pair order when the sidebar is on the right
- the glance split action disables when split capacity is already full
- clicking outside an unfocused glance dismisses it if the page does not block
  dismissal through an unload prompt
- focused close requires an explicit second confirmation window before commit
- closing the parent closes the live glance
- dismissing glance returns focus to:
  1. the parent tab if still alive
  2. the focused split item in the same space if applicable
  3. the most recently used tab in the same space
- workspace filtering never hides a live glance and space moves must mirror the
  parent workspace onto the live glance child

## Address bar behavior

- there is one canonical address bar implementation for attached, floating, and
  compact-reveal presentation
- opening a new tab focuses the address bar instead of creating a blank tab
  first
- pressing `Ctrl` or `Cmd` + `T` while the address bar is already open closes
  it
- pressing `Esc` closes the address bar and restores focus to the previously
  focused surface
- blurring the window does not close the address bar
- command actions rank above general navigation and search results
- typing a space name may switch spaces directly
- typing an extension name may open that extension directly
- typing a URL or bare domain shows both direct navigation and explicit search
  fallback results
- overflowing extension actions render below the address bar in single-sidebar
  mode instead of silently falling back into the site controls hub

## Compact mode behavior

- compact mode is one window-scoped shell state, not an ad hoc per-view effect
- hidden chrome reveals only from explicit edge hover zones or keyboard toggle
- hover reveal auto-hides after the configured delay once the pointer leaves
  the revealed chrome
- while dragging, compact reveal stays open for the active valid drop zone
- compact mode must not leave the address bar visually stuck in floating state
- compact mode and split view must coexist without broken layout
- fullscreen hides compact borders and split chrome without corrupting layout
- hover and reveal logic must come from one centralized controller, not many
  local observers

## Keyboard semantics

- keyboard shortcuts are customizable, but their action semantics are frozen
- `Ctrl` or `Cmd` + `L` focuses the address bar
- `Tab` on an empty command bar shows all commands
- default macOS `switch to N space` bindings mirror Zen's `control + number`
  behavior
- numbered tab targeting counts essentials first, then pinned items, then
  regular tabs
- MRU tab traversal stays inside the current space
- page history shortcuts must never be misrouted into space switching

## Focus and close rules

- tab close follows MRU focus first
- if no MRU candidate exists, focus the nearest visible sibling below, then
  above
- if a split item closes, focus stays inside the split if another item remains
- if closing the last tab in a space, fall back to that space’s blank/new tab
  affordance
- space switching preserves per-space selection and restores it when returning

## Non-goals for this pass

- cross-window drag semantics
- live-folder behavior
- window-sync behavior
- onboarding or settings interactions
