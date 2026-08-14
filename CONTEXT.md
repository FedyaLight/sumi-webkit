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

**Private Partition**:
A non-durable browsing partition shared only by explicitly related incognito windows. It pairs one non-persistent `WKWebsiteDataStore` with memory-only Sumi state keyed by the same UUID and is destroyed after its final window lease closes.
_Avoid_: Incognito profile, temporary Browser Profile

## Content Blocking Language

**Blocker Rule Inventory**:
The Browser-Database-owned projection of which Safari content-blocker rule lists are enabled and the identity of each compiled WebKit rule list. Browser read paths answer from this projection; extension bundle contents are read only while installing, refreshing, or recovering a missing compiled list.
_Avoid_: Rule cache, blocker manifest

## Split View Language

**Durable Page Identity**:
The stable identity of a page in browser state, independent of whether its live web content is currently materialized, unloaded, or presented in more than one window.
_Avoid_: WebView identity, loaded tab

**WebView Residence**:
The exact window-scoped placement of one materialized page instance. A Durable Page Identity may outlive every residence and may have distinct residences in different windows.
_Avoid_: Tab-owned WebView, global page view

**Media Fullscreen Session**:
A native system presentation initiated by media in one page. It remains bound to that page, but does not own the browser's current tab or Space selection: changing that selection does not end the presentation, and ending the presentation does not roll the selection back. The browser requests its end only when the initiating page itself is explicitly destroyed.
The window host may read WebKit's current fullscreen placeholder as the displayed AppKit view, but never creates, replaces, or commands that placeholder.
_Avoid_: Fullscreen-protected tab, browser fullscreen overlay

**Sidebar Mini Player**:
Browser-owned controls for media playing in background pages, presented in the sidebar. Clicking the card explicitly activates the source tab. Its separate play, pause, and mute commands act through the page's native media session without selecting a tab or Space, changing focus, or materializing a page. The Mini Player is independent of the native Media Fullscreen Session and native system media controls.
_Avoid_: Media Touch Bar, fullscreen controls

**Page Media Session**:
The page-scoped native media session that supplies metadata and accepts media commands for one Durable Page Identity and exact WebView Residence generation. Global system Now Playing state is never its identity.
_Avoid_: Audio tab, system media session, current Now Playing app

**Retained Paused Session**:
A Page Media Session explicitly paused through the Sidebar Mini Player and retained as a card only while its exact WebView Residence stays in the background. Page Activation consumes that presentation retention without issuing a playback command; leaving the still-silent page cannot recreate the card. Only a later native audible playback epoch may admit it again.
_Avoid_: Paused card owner, last played tab, stale media card

**Retained Muted Session**:
A Page Media Session explicitly muted through the Sidebar Mini Player and retained as a card only while its exact WebView Residence stays in the background. Page Activation consumes that presentation retention. A page that was already muted outside the Sidebar Mini Player is never admitted on this basis.
_Avoid_: Muted tab card, silent media owner

**Dismissed Media Session**:
A Page Media Session whose Sidebar Mini Player close command paused its native media and removed its card. Page Activation never resumes it; only a later audible playback epoch may admit it again.
_Avoid_: Hidden playing card, temporarily closed player

**Split Group**:
A durable sidebar item containing two to four ordered page identities and one layout. The group keeps its identity when moved between Regular, Pinned, Folder, and Favorite.
_Avoid_: Split placeholder row, ghost row

**Regular Member**:
A split participant owned by a Space's regular tab collection.
_Avoid_: Unsaved launcher

**Launcher Member**:
A split participant owned by Pinned, a Pinned folder, or Favorite. A launcher may be loaded or unloaded without changing its durable identity; a saved launcher with no prior runtime session remains unloaded and is never background-loaded.
_Avoid_: Placeholder tab

**Shortcut**:
A saved site launcher in the sidebar whose durable identity does not depend on whether its runtime page is currently materialized.
_Avoid_: Keyboard shortcut, key binding, hotkey

**Group Activation**:
Loading every runtime page of a launcher-backed split and focusing one participant. Individual launcher members cannot be loaded or unloaded independently while grouped.
_Avoid_: Member activation, partial loading

**Group Unload**:
Retiring every runtime page of one launcher-backed Split Group in a window without changing its durable identity. If that group is presented, the window moves to a valid fallback; if it is backgrounded, the current selection and presented WebView remain unchanged.
_Avoid_: Split dismissal, global unload

**Container Conversion**:
An atomic replacement of every member identity when a whole split group moves between Regular and launcher-backed containers. The group itself is not duplicated or dissolved.
_Avoid_: Split copy, group recreation

**Favorite Split Tile**:
One Favorite grid item representing an entire split group. Its participants do not consume additional Favorite grid slots.
_Avoid_: Split member tiles

**Favorite Selection Material**:
The site-derived visual treatment applied to a selected Favorite or Favorite Split Tile. It belongs only to the Favorite presentation and is never applied to Regular or Pinned launchers.
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

**Page Materialization Request**:
The exact window-local owner that turns one accepted Page Activation of a Cold Page into one WebView Residence and transfers its first destination once to a Page Navigation Attempt. It is identified by Durable Page Identity, window, selection revision, and residence generation; supersession or departure settles it, and late work can only clean up its unpublished candidate.
_Avoid_: WebView creation, lazy tab load, scheduled materialization

**Page Presentation**:
The window-local projection for one selected Durable Page Identity: Empty Page, neutral non-live placeholder, live committed frame, or actionable Recovery Failure Surface. Preparation, restore, cleanup, and loading remain typed lifecycle state but do not expose browser-internal status text over web content. Presentation may attach an existing residence but never creates a WebView or starts navigation.
_Avoid_: Selected WebView, pane contents, transparent host

**Live Page**:
A Durable Page Identity with at least one materialized WebView Residence. Activation in a window that owns a live residence reveals that residence's real current frame without restoration or a new navigation; another window may still require its own Page Materialization Request.
_Avoid_: Warm tab, cached page

**Cold Page**:
A durable page identity without a materialized WebView. Browser-session ports are shared rather than copied into every Cold Page, and WebKit-bound caches stay unmaterialized until selection or explicitly enabled warmup. It may retain resumable browsing state within the current app run, but across launches it resumes from its durable URL and ordinary persisted metadata.
_Avoid_: Slow page, dead tab

**Page Session Snapshot**:
Optional opaque WebKit history and interaction state captured from one exact committed WebView Residence for an in-process resume. It is keyed by page, window, residence generation, profile/partition, and committed-destination revision; it is never durable destination authority, never shared across residences, and is consumed only after a concrete native restore navigation binds.
_Avoid_: Saved tab state, durable session, tab-wide interaction data

**Page Suspension**:
Atomic resource retirement of every eligible WebView Residence for one Durable Page Identity while preserving its Last Committed Destination and any exact Page Session Snapshots. Allocation of a replacement WebView does not end suspension; a bound restore or ordinary destination fallback must commit or terminate visibly.
_Avoid_: Hidden tab, paused WebView, unloaded flag

**Empty Page**:
An explicitly created Durable Page Identity with no committed web destination. It presents browser-owned empty or new-tab content until a destination is accepted; a platform initial empty document is not its durable URL.
_Avoid_: Blank tab URL, repaired tab, initial about:blank

**Last Committed Destination**:
The latest main-frame destination accepted as the real content of a Durable Page Identity. A provisional navigation, platform initial empty document, isolated cleanup document, recovery placeholder, or unadmitted blank document does not replace it. An Empty Page has no such destination; an intentionally admitted blank document may.
_Avoid_: Current URL, fallback URL, last request

**Page Navigation Attempt**:
One accepted effort to move a Durable Page Identity toward a destination, spanning browser-owned preparation and the native page lifecycle. It either transfers once into that lifecycle or ends through cancellation, failure, supersession, or owner departure; a later attempt never inherits its terminal events.
_Avoid_: Scheduled load, pending reload, loading flag

**Automatic Glance Policy**:
The browser-owned choice to present an admitted new tab-like navigation from an eligible pinned source as a temporary Glance instead of using its ordinary tab presentation. The choice depends on navigation semantics and user intent; Live versus newly materialized residence never changes it.
_Avoid_: Pinned-link rule, cross-host preview heuristic, automatic popup

**Ordinary Navigation Outcome**:
The page, frame, tab, popup, download, or external handling that an admitted navigation receives when no browser-owned presentation command supersedes it. Choosing not to use Glance preserves this outcome; it never means silently cancelling the navigation.
_Avoid_: Glance fallback, allow policy, no-op navigation

**Page Reload Command**:
A user request to revalidate the exact current native history item in the same WebView Residence. It creates a new Page Navigation Attempt and either binds a concrete native reload, names the exact owner it waits or coalesces behind, or fails terminally; it never silently becomes fresh-runtime replacement or URL-only reconstruction.
_Avoid_: Refresh flag, reload request, best-effort retry

**Page Navigation Prerequisite**:
Browser-owned work that must settle before a Page Navigation Attempt may transfer to, or continue through, the native page lifecycle. It has one exact owner and terminal disposition; an optional subsystem may participate only when it cannot leave the attempt unterminated.
_Avoid_: Startup wait, loading dependency, async gate

**Blank Document Admission**:
The proof that an exact Page Navigation Attempt intentionally targets an `about:blank` main-frame document and may publish it as content. It preserves whether the source was an explicit browser command, a site navigation, a child or popup creation, or an isolated browser operation; the URL string alone is never proof.
_Avoid_: Blank allowlist, about-scheme check, empty-page flag

**Page Navigation Authority**:
The one Live Page participant in the current Page Navigation Attempt allowed to publish shared destination and loading state. Other residences retain only local evidence until an exact promotion; visibility and callback arrival order never grant authority.
_Avoid_: Current WebView, visible page, latest callback

**Page Recovery**:
Restoring a Durable Page Identity to its Last Committed Destination after its live WebKit content terminates or becomes unusable, without creating a new page identity.
_Avoid_: Blank-page reload, tab recreation, crash redirect

**Page Recovery Epoch**:
The event-bounded allowance for one automatic recovery of a logical committed-document lineage. Repeated termination does not reset it; only a user-authorized action that produces a new admitted committed document begins another epoch.
_Avoid_: Crash timeout, reload counter, retry window

**Fresh Page Repair**:
An explicit user-authorized replacement of unusable WebView Residence generations while preserving Durable Page Identity, Last Committed Destination, container/group membership, and every healthy residence. It is separate from native Reload and never claims to reconstruct non-idempotent request state from a URL.
_Avoid_: Hard reload, launcher unload, tab recreation

**Recovery Failure Surface**:
The explicit user-visible state presented when automatic Page Recovery cannot restore usable content. It preserves the Last Committed Destination and offers a deliberate retry instead of presenting recovery as `about:blank` or endless loading.
_Avoid_: Failed blank page, stuck loader, silent recovery

**Page Runtime Retirement**:
The terminal release of an exact WebView Residence generation. It settles navigation, policy, authentication, recovery, media, user-content, and lifecycle ownership before delegate removal and physical WebKit release; the Durable Page Identity may survive as Cold, suspended, or failed.
_Avoid_: WebView cleanup, tab unload, view removal

**Website Data Mutation**:
An exclusive profile- or partition-scoped operation that isolates exact live WebView residences, mutates WebKit-owned website data, and transfers every touched residence once to a normal bound navigation or terminal page state. It performs no indefinite retry or ordinary page-load timeout.
_Avoid_: Clear-cache navigation, browser reset, cleanup loop

**Cleanup Navigation**:
A typed, non-authoritative physical navigation owned only by a Website Data Mutation. Its blank document and lifecycle callbacks never publish page destination, history, loading, persistence, or recovery state.
_Avoid_: Temporary page, blank reload, cleanup tab

**Restore Failure Surface**:
The explicit browser-owned state for a persisted page record whose destination or native session state cannot be reconstructed safely. It preserves the Durable Page Identity and repair reason without inventing a destination or impersonating an Empty Page.
_Avoid_: Repaired blank tab, dropped corrupt tab, restore placeholder URL

**Sidebar Pointer Session**:
The single exclusive pointer interaction for one Sidebar Visual Item in a window, from press through Page Activation, drag, or a release-only action until completion, cancellation, replacement, or disappearance. Presentation changes, including materialization and temporary gaps between AppKit owners, preserve both the session and its drag owner so the accepted press can cross the drag threshold without a second gesture. While a session is accepted it drives drag and release from the window's event stream rather than from press-time view routing, so the item presenting the session now receives the rest of the gesture. Temporary interaction disablement may prevent new input but does not cancel an accepted session. Every item accepts its press visual with the session, whether or not Page Activation must materialize it. That visual is presented for a minimum perceptible interval counted from the first frame it could be drawn, so synchronous materialization cannot swallow it; a release inside that interval is honored when it ends, while a drag, a cancellation, or a press on another item ends it at once. Page Activation is accepted on press; release accepts only a release-only action of the same identity. Starting a session cancels the previous one, and hover is reconciled once after drag ends.
_Avoid_: Row click state, sticky hover, parallel drag flag

**Sidebar Hover Session**:
The window-local authority that derives hover for every registered sidebar region from current geometry. Native enter/exit events request reconciliation but never own truth; drag and transient sessions suspend hover once at this authority. Nested regions may both be hovered when geometry contains the pointer. A visually overlaid region may declare an occluding hover layer; while the pointer is inside it, only that layer and higher-priority nested controls may publish hover, so covered sidebar items cannot react through the overlay.
_Avoid_: Paired enter/exit truth, row-owned hover lifecycle, continuous mouse-move polling

**Presented Drop Intent**:
The exact sidebar destination currently communicated by the visible drop gap. A completed drop commits that same destination even if rendering the gap changes surrounding geometry.
_Avoid_: Recomputed drop target, approximate hover slot

**Presented Sidebar Layout**:
The current window-local geometry of Sidebar Visual Items as they are actually drawn, including transient positions during an animation. Rendering, hit testing, and the visible gap for Presented Drop Intent observe this same layout.
_Avoid_: Target sidebar geometry, reconstructed drag frames

**Presented Sidebar Layout Phase**:
The window-local statement that Presented Sidebar Layout is moving toward a visible or hidden position, or has settled there. A requested target is not settled; only completion of that same uninterrupted presentation makes it settled. Transitional stand-ins and native window controls derive their visibility from this phase.
_Avoid_: Nominal-duration settlement, pointer-intent generation, independently reconstructed chrome state

**Drag Presentation**:
The target-adaptive appearance of one Sidebar Visual Item while it is being moved. It preserves item identity while matching the row, folder, or Favorite surface of the current Presented Drop Intent.
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
A browser behavior with one stable identity, presentation, availability rule, optional Key Binding, and execution route shared by Keyboard Command Dispatch and the Command Palette.
_Avoid_: Palette-only command, duplicate shortcut action

**Browser Action Projection**:
The exact-window presentation of one Browser Action: its menu and Command Palette titles, active or unassigned Key Binding, and current availability. Presentation surfaces read this projection, while execution revalidates the same identity against the same window.
_Avoid_: Menu shortcut model, palette command copy, action closure row

## Keyboard Command Language

**Key Binding**:
The user-configurable pairing of a key combination with one Browser Action.
_Avoid_: Keyboard shortcut, hotkey, shortcut

**Keyboard Command Dispatch**:
The window-scoped resolution of a keyboard event to its native responder command, Browser Action, extension command, or transient-surface command.
_Avoid_: Global shortcut handling, key interception

**Command Authority**:
The AppKit key-equivalent and responder-chain path that owns standard editing, focused-surface commands, and menu-exposed Browser Actions.
_Avoid_: Monitor-first dispatch, global shortcut router

**Command Ownership**:
The exclusive assignment of one Key Binding to one command domain before event delivery. Runtime unavailability never transfers that binding to another command domain.
_Avoid_: Runtime fallback chain, first handler wins

**Extension Command**:
A manifest-declared extension behavior identified by one extension identity and command name. Its manifest key is only a Suggested Binding; its active binding and ownership belong to the Browser Profile.
_Avoid_: Extension shortcut, manifest accelerator

**Unsupported Extension Command**:
An Extension Command whose media-key or global activation capability Sumi does not implement. It remains declared and reports no active binding, owns no event, and is never downgraded to regular in-app delivery.
_Avoid_: Disabled regular command, best-effort global command

**Extension Command Adapter**:
The window-scoped route from an active extension Key Binding to its loaded extension command after native and Browser Action ownership have been excluded.
_Avoid_: Extension shortcut router, extension fallback chain

**Native Reservation**:
A key combination owned exclusively by macOS, AppKit editing, or the focused responder and unavailable to Browser Actions or extension commands.
_Avoid_: Hard-coded shortcut exception, system-owned Browser Action

**User Binding**:
The one active Key Binding explicitly assigned by the user to a Browser Action or extension command.
_Avoid_: Winning shortcut, runtime-selected binding

**Suggested Binding**:
A default Browser Action or extension-manifest Key Binding candidate that becomes active only when its combination has no owner.
_Avoid_: Default active binding, fallback binding

**Binding Assignment Projection**:
The window-and-profile-specific view that gives one authoritative owner or inactive reason for every Key Binding across Browser Actions, extensions, and Native Reservations.
_Avoid_: Shortcut lookup table, merged shortcut cache

**Inactive Binding**:
A preserved User Binding or Suggested Binding that owns no keyboard command because it conflicts with current policy, while retaining the reason it needs reassignment.
_Avoid_: Invalid shortcut, discarded override

**Transient Command Scope**:
The window-local period in which an attached surface participates in AppKit key-equivalent and responder delivery. Attachment, key-window membership, and responder position define the scope; visibility alone does not.
_Avoid_: Visible overlay priority, transient shortcut mode

**Focus Return Target**:
The responder that owned focus before a transient surface took it and is restored when that surface ends if it still belongs to the same window.
_Avoid_: Previous focus flag, global active control

**Keyboard Capture Session**:
Temporary exclusive keyboard ownership held only while the Key Binding recorder is the focused responder, ending on commit, cancellation, focus loss, or teardown.
_Avoid_: Recorder mode flag, shortcut monitor session
