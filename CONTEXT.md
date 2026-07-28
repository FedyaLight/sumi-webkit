# Sumi Browser

Sumi presents pages through regular tabs and saved launchers. Split groups are durable sidebar items whose runtime pages are projected into a window when the group is active.

## Persistence Language

**Local Installation**:
The complete set of Sumi-owned data for one installed copy of the app on one macOS user account.
_Avoid_: Local profile, old-user store

**Browser Profile**:
A durable browsing persona inside a Local Installation. Its browser-owned records are identified by one profile UUID, while its website data remains owned by WebKit under the same UUID.
_Avoid_: Account, installation profile

**Browser Database**:
The single transactional SQLite database containing Sumi-owned structured browser data for a Local Installation.
_Avoid_: Startup store, bookmark database, profile database

**Platform Store**:
A specialized store whose lifecycle is owned by macOS or WebKit, such as Keychain or `WKWebsiteDataStore`, and which is referenced but never reimplemented by the Browser Database.
_Avoid_: Legacy store, auxiliary database

## Split View Language

**Split Group**:
A durable sidebar item containing two to four ordered page identities and one layout. The group keeps its identity when moved between Regular, Pinned, Folder, and Essentials.
_Avoid_: Split placeholder row, ghost row

**Regular Member**:
A split participant owned by a Space's regular tab collection.
_Avoid_: Unsaved launcher

**Launcher Member**:
A split participant owned by Pinned, a Pinned folder, or Essentials. A launcher may be loaded or unloaded without changing its durable identity; a saved launcher with no prior runtime session remains unloaded and is never background-loaded.
_Avoid_: Placeholder tab

**Group Activation**:
Loading every runtime page of a launcher-backed split and focusing one participant. Individual launcher members cannot be loaded or unloaded independently while grouped.
_Avoid_: Member activation, partial loading

**Group Unload**:
Retiring every runtime page of one launcher-backed Split Group in a window without changing its durable identity. If that group is presented, the window moves to a valid fallback; if it is backgrounded, the current selection and presented WebView remain unchanged.
_Avoid_: Split dismissal, global unload

**Container Conversion**:
An atomic replacement of every member identity when a whole split group moves between Regular and launcher-backed containers. The group itself is not duplicated or dissolved.
_Avoid_: Split copy, group recreation

**Essential Split Tile**:
One Essentials grid item representing an entire split group. Its participants do not consume additional Essentials grid slots.
_Avoid_: Split member tiles

**Essential Selection Material**:
The site-derived visual treatment applied to a selected Essential or Essential Split Tile. It belongs only to the Essentials presentation and is never applied to Regular or Pinned launchers.
_Avoid_: Pinned backdrop, global launcher gradient

**Sidebar Visual Item**:
One ordered sidebar identity presented and moved as a whole. A regular tab, launcher, folder, or Split Group each occupies one visual position regardless of the number of durable records behind it.
_Avoid_: Render row record, split member slot

**Folder Expansion**:
The durable open or closed state of a saved folder, shared across every window presenting that folder. Window-local animation and drag preview never create a second expansion truth.
_Avoid_: Window-local folder state, rendered open flag

**Folder Drop Preview**:
A temporary window-local opening of a saved folder while a drag targets its contents. It ends on drop or cancellation and never changes Folder Expansion.
_Avoid_: Auto-opened folder, drag-mutated expansion

**Folder Expansion Transition**:
The interruptible window-local visual movement toward the latest Folder Expansion revision. It never delays, merges, or rejects accepted expansion commands.
_Avoid_: Expansion debounce, click gate, animation-owned state

**Space Pinned Collapse**:
The persisted window-local choice to present one Space's Pinned content either in full or condensed to its selected and live sticky projections. It never changes Folder Expansion or the saved-content inventory.
_Avoid_: Collapsed Space, hidden Pinned state

**Space Pinned Disclosure Transition**:
The interruptible window-local visual movement toward the latest Space Pinned Collapse value. A nested sticky destination may appear from the first frame while its full-presentation occurrence departs; this never creates a second selection or saved item and never delays, merges, or rejects collapse commands.
_Avoid_: Pinned fade, collapse debounce, duplicated selected item

**Sidebar Mutation Order**:
The single window-observable order of saved-content structural changes and Folder Expansion revisions. A later revision for the same identity cannot be overwritten by an older presentation snapshot.
_Avoid_: Independent UI update order, best-effort snapshot delivery

**Page Activation**:
Selecting a regular tab, launcher, or Split Group participant so its runtime page is presented in the window. A press accepts Page Activation immediately; every accepted activation of a Live Page is presented without coalescing, while superseded Cold Page preparation never changes the newer selection. A later drag or release outside does not roll activation back. Nested controls never trigger Page Activation for their parent Sidebar Visual Item.
_Avoid_: Release selection, provisional selection

**Live Page**:
A runtime page whose WebView remains materialized and can be presented without restoration or a new navigation. Page Activation of a Live Page is expected to reveal its real current frame immediately.
_Avoid_: Warm tab, cached page

**Cold Page**:
A durable page identity without a materialized WebView. Browser-session ports are shared rather than copied into every Cold Page, and WebKit-bound caches stay unmaterialized until selection or budgeted warmup. It may retain resumable browsing state within the current app run, but across launches it resumes from its durable URL and ordinary persisted metadata.
_Avoid_: Slow page, dead tab

**Sidebar Pointer Session**:
The single exclusive pointer interaction for one Sidebar Visual Item in a window, from press through Page Activation, drag, or a release-only action until completion, cancellation, replacement, or disappearance. Presentation changes, including materialization and temporary gaps between AppKit owners, preserve both the session and its drag owner so the accepted press can cross the drag threshold without a second gesture. While a session is accepted it drives drag and release from the window's event stream rather than from press-time view routing, so the item presenting the session now receives the rest of the gesture. Temporary interaction disablement may prevent new input but does not cancel an accepted session. Every item accepts its press visual with the session, whether or not Page Activation must materialize it. That visual is presented for a minimum perceptible interval counted from the first frame it could be drawn, so synchronous materialization cannot swallow it; a release inside that interval is honored when it ends, while a drag, a cancellation, or a press on another item ends it at once. Page Activation is accepted on press; release accepts only a release-only action of the same identity. Starting a session cancels the previous one, and hover is reconciled once after drag ends.
_Avoid_: Row click state, sticky hover, parallel drag flag

**Sidebar Hover Session**:
The window-local authority that derives hover for every registered sidebar region from current geometry. Native enter/exit events request reconciliation but never own truth; drag and transient sessions suspend hover once at this authority. Nested regions may both be hovered when geometry contains the pointer.
_Avoid_: Paired enter/exit truth, row-owned hover lifecycle, continuous mouse-move polling

**Presented Drop Intent**:
The exact sidebar destination currently communicated by the visible drop gap. A completed drop commits that same destination even if rendering the gap changes surrounding geometry.
_Avoid_: Recomputed drop target, approximate hover slot

**Drag Presentation**:
The target-adaptive appearance of one Sidebar Visual Item while it is being moved. It preserves item identity while matching the row, folder, or Essentials surface of the current Presented Drop Intent.
_Avoid_: Drag snapshot copy, generic ghost

**Split Group Row Presentation**:
The canonical row appearance of a Split Group across live, transition, and drag surfaces. Member order, pill geometry, title visibility, icon treatment, and selection material do not vary by surface.
_Avoid_: Split row variant, snapshot split row

## Command Palette Language

**Command Palette Session**:
One window-bound interaction from presentation until one accepted commit or dismissal. Query generations, modes, rows, selection, preview, and commit all belong to this session and may never fall back to another active window.
_Avoid_: Global command bar state, active-window palette

**Palette Row**:
A stable semantic result identity plus the presentation needed to render it. Browser objects and execution closures remain behind the Command Palette Session seam.
_Avoid_: Suggestion index, view-specific result

**Palette Mode**:
The exclusive search scope of a Command Palette Session: Everything, Actions, or one site-search engine. Spaces and extensions are result kinds inside Everything and Actions. A mode offer is not a mode until the user accepts it.
_Avoid_: Parallel mode flags, tab-search state

**Browser Action**:
A browser behavior with one stable identity, presentation, availability rule, optional shortcut, and execution route shared by keyboard shortcuts and the Command Palette.
_Avoid_: Palette-only command, duplicate shortcut action
