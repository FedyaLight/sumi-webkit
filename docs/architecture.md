# Architecture

Sumi Browser is a native macOS app built around system WebKit, SwiftUI, and
AppKit where platform integration requires it. The repository name emphasizes
the WebKit direction, but the public product name is Sumi Browser.

The current target is macOS 15.5+.

## Target Module Graph

The repository keeps only two package boundaries with independent tests and
meaningful reuse constraints:

```
SumiDomain
SumiWebRuntime

Sumi App ──► SumiDomain
         └─► SumiWebRuntime
```

- **SumiDomain** — Foundation-only models and policies.
- **SumiWebRuntime** — WebKit session / navigation runtime (no SwiftUI).
- **Sumi App** — process composition, browser-runtime ports and events, shell
  UI, layout tokens, hubs, and command routing.

## Current Reality

Browser shell UI, its layout tokens, and the tab-structure event bus remain in
the app target because they have no independent consumer or lifecycle. A
package is not used merely to split a handful of source files: source folders
and narrow app-internal types carry those responsibilities without adding a
manifest, product, dependency edge, or duplicate test lane.

Hub façade sizes are frozen by `scripts/check_architecture_hub_metrics.sh`.
Generic `*Owner` names in existing code are legacy architecture debt, not the
preferred decomposition model. New extraction names the concrete role or
transaction it owns; touched god objects are split by cohesive responsibility
instead of gaining another generic owner wrapper. Runtime ports live under
`Sumi/BrowserRuntime/` in the app target, including the UUID-only split
coordination port.

## WebView Session Ownership

`SumiApp` creates exactly one `WebViewSessionRepository` for a browser process.
The composition root passes it to `BrowserManager`, `TabManager`, and
`WebViewCoordinator`; production tabs are created by `TabFactory` on that same
repository. Runtime code validates repository identity and never migrates
ownership between repositories.

The repository is the placement source of truth:

- `WebViewSessionHandle` exposes one tab's detached/parked state and reads.
- Window-slot mutations are package-scoped behind
  `WebViewTrackingLifecycleOwner`, keeping index changes and lifecycle side
  effects inseparable.
- A concrete `WKWebView` has one residence: parked, untracked, one
  `(tab, window)` slot, or an exclusive pending-cleanup lease.
- Whole live-window rebuilds create the complete provisional set, then use one
  snapshot/revision compare-and-swap commit before cleaning the old set.
- Revision tracking rejects absent/present/absent ABA transactions without
  retaining closed-tab UUID tombstones.
- Replacing or releasing a detached/parked view atomically transfers the
  displaced residence into `pendingCleanup`; there is no intermediate
  ownerless state. An exact lease is consumed immediately before shutdown, so
  a stale command cannot destroy a reused view and a leased view cannot return
  to an active slot.
- `trackedWebViews(in:)` is backed by a repository-owned
  `windowID -> Set<tabID>` identity index. The index changes in the same
  mutation as the canonical store and is checked by repository consistency
  assertions; it never becomes a second owner of `WKWebView` instances.

Protected compositor mutations use per-source, semantic-key deduplicated
commands. The buffer has a soft shedding capacity: best-effort maintenance is
dropped or displaced at the threshold, while unique destructive or explicit
navigation work may temporarily exceed it rather than be lost. Deferred
commands use directional effect dominance only when the newer operation is
proven to perform every effect of the older command for the same exact scope;
window, tab, detached-cleanup, and WebKit-close effects are never conflated.
Superseded commands are reported to the normal drop/diagnostic path, and a
failed command is not restored in front of a newer proven dominator. Deferred
navigation rebuilds resolve and retain their target, configuration, semantic
kind, and monotonic intent revision before deferral; maintenance rebuilds
cannot replace pending semantic navigation, and stale intents are rejected.
Cross-window URL propagation uses the same rule: each protected tracked view
receives a guaranteed, latest-wins command keyed by its concrete WebView and
validated against both its exact `(tab, window)` owner and the originating
navigation revision. Releasing protection replays the current command; a newer
navigation or residence change prunes it. Each participating WebView has one
explicit delivery phase (`preparing`, `deferred`, `submitted`, `active`, or
`completed`), so readiness, protection replay, and direct submission compete
through one state transition instead of independent booleans. A nil WebKit
submission restores a protected delivery to `deferred`; it is never consumed
as success. Views already awaiting their own initial/explicit load are
excluded from broadcast, preventing a readiness race from loading the same
document twice.
The final protection check, queue removal, and command execution are one
contiguous main-actor operation. Re-protection therefore leaves the command
queued instead of executing it through a check/use gap. When global teardown
removes compositor protection, every command it makes executable is explicitly
flushed. A failed guaranteed execution is restored to its FIFO position and
retried with capped exponential backoff until it succeeds, becomes invalid, or
the terminal browser-session reset cancels it; it is never consumed as success
or stranded after a retry budget.

Promoted Glance hosts use a typed handoff state machine. Registration requires
a live compositor container; successful take/attach resolves `.attached`,
while replacement or window/global teardown resolves `.cancelled` exactly once.
Each compositor installation also owns an identity lease. A stale controller
cannot unregister a replacement container or run window-global fullscreen,
handoff, or host teardown for the replacement. Every queued display, host,
focus, hover, repair, and delayed visual mutation revalidates that exact lease
before touching AppKit state, so a superseded controller cannot reparent the
canonical WebView into its obsolete hierarchy. Visual-handoff protection is
itself an exact lease, not a boolean, and only its owner can release it.
History-swipe transactions likewise retain the exact source WebView across
primary-window changes; cancellation, timeout, overlap, and regular-navigation
settlement release that source rather than whichever clone is currently
primary.

Initial-document handoff captures both a semantic navigation intent
`{revision, targetURL}` and the exact repository residence of its `WKWebView`.
After every suspension, and immediately before loading, both must still match.
The readiness ticket owns the revision, while the load resolves the latest
target for that revision after the gate; an accepted redirect therefore moves
a waiting sibling to the redirect target without admitting a second load.
Thus a delayed initial load cannot overwrite newer navigation or follow the
same view after it has moved to another window. `stopLoading` invalidates the
semantic intent as well as the WebKit transaction, and initial handoff supports
file URLs through `loadFileURL` rather than treating HTTP as the only initial
document class.

Main-frame model mutation is authorized by the exact
`ObjectIdentifier(BrowserServicesKit.Navigation)`, pre-bound to every
browser-owned `WKNavigation` through `ExpectedNavigation`. One WebView is the
authority for a semantic revision; sibling callbacks remain participants but
cannot mutate shared `Tab` state. Trusted client-redirect and same-document
continuations may transfer that authority only on the same WebView and within
the same still-current revision. User supersession requires WebKit's explicit
user-initiation signal. When an authoritative WebView leaves the runtime,
authority is promoted to an already-active sibling before delegates are
removed. Completed identities are discarded, preventing allocator-address ABA
from reviving an old transaction. `Tab.url` is presentation/persistence state,
not navigation identity; only command and accepted lifecycle APIs advance the
semantic intent. URL comparisons use one canonical identity for default ports,
empty HTTP paths, file paths, and percent escapes.

`Tab` retains one main-frame runtime aggregate and cannot retain its mutable
components separately. The intent ledger owns semantic submissions and
deferred loads; the lifecycle machine coordinates exact physical participants,
logical authority, and one-shot effect claims; the committed-document ledger
is the durable rollback source even after every physical replica disappears;
and the WebContent recovery planner owns exact per-WebView recovery markers.
Transitions that cross those boundaries run through the aggregate on the main
actor. This prevents a physical clone, a pending submission, or a process-crash
retry from silently becoming navigation authority by mutating only one store.
The ownership guard rejects production construction of those components
outside the aggregate and rejects direct component storage on `Tab`.

## Runtime Assembly

`WebViewCoordinator` receives one `WebViewRuntimeEnvironment` containing its
browser, visible-preparation, initial-document, and shutdown capabilities.
Environment attachment and detachment are atomic, so runtime code cannot
observe a partially wired coordinator. The production
`BrowserManager`-to-`WebViewCoordinator` identity is different: it is bound
exactly once for the browser-session lifetime. Replacement or detachment is a
composition failure, and cleanup requires that binding instead of silently
falling back to partial teardown. The process-owned coordinator and repository
outlive a deallocated manager; a late window-close callback therefore performs
full repository-owned window cleanup, not compositor-only cleanup.

`TabManager` side effects use immutable typed ports. The live ports share one
explicit browser-session lifetime reference: using a port after the owning
session is released is a composition failure, not a silent no-op. No-op port
registries exist only in test support. Persisted tab restore starts only after
runtime ports, the window registry, and the WebView coordinator are attached;
it compares a structural mutation revision across its asynchronous load and
rejects stale snapshots instead of overwriting live changes. Initial-data
readiness is replayed to late subscribers.

## Browser Shell

The main browser shell is organized around:

- Tabs for ordinary page navigation.
- Spaces for separating groups of tabs within a profile.
- Profiles for separating larger browsing contexts.
- Sidebar-first organization for tabs, spaces, pinned items, essentials, and
  folders.
- Glance for opening a page over the current tab without taking layout space.
- Split view for viewing up to four pages together.
- Floating bar for search, address entry, suggestions, site search, history,
  bookmarks, and split-aware actions.

Glance can close quickly, expand into a normal tab, or move into split view.
Pinned and essential items can also open through Glance-style launcher flows.

Essentials are global across spaces that belong to the same profile. Pinned
items live in one space and look like normal tabs. Essentials appear as tiles.

## Launcher Semantics

Sumi separates visible organization from live page runtime where possible.
Pinned and essential items can preserve their visible identity while the live
WebView/runtime instance is unloaded to free memory. This is a design and
implementation behavior, not a benchmark claim.

## Performance Principles

Sumi is performance-first in the sense that browser features should have clear
lifecycle ownership and should avoid hidden work.

Current principles:

- Use system WebKit for page rendering.
- Prefer native SwiftUI/AppKit browser chrome over heavy web UI.
- Keep optional modules lazy.
- Disabled modules should not create background runtime work.
- Avoid background services and timers unless they are necessary.
- Preserve visible tab, pinned, essential, and folder organization when
  inactive live page runtimes are unloaded.
- Keep extension service-worker behavior aligned with Safari's event-driven model.
- Index identity and ordering lookups on restore/selection hot paths instead of
  repeatedly scanning tab, pin, folder, or WebView collections.

Memory modes exist in the UI, and inactive tab unloading exists. The goal is to
preserve user organization while reducing unnecessary live runtime state.

## Optional Modules

Extensions, userscripts, and privacy cleanup are feature areas that should
remain optional. When disabled, they should avoid background runtime cost.

## Protection

Tracking Protection and Adblock are owned by the native content-blocking
runtime under `Sumi/ContentBlocking`. Sumi consumes prepared bundles from
`sumi-protection-bundles`, verifies their manifests and shard hashes, compiles
the selected groups through WebKit, and keeps the previous generation available
for rollback. The browser must not fetch raw filter lists, parse ABP/uBO syntax,
run `adblock-rust`, or convert DuckDuckGo Tracker Radar data at runtime.

## Extensions

Safari extension support is built around `WKWebExtensions`. The active milestone
is real-world password-manager extension compatibility.

Normal browsing views are the default extension participation surface. Helper
surfaces such as favicon downloads, previews, and mini windows should not
participate unless a future design explicitly opts them in.

## AI Policy

Sumi does not include a built-in AI panel. AI tools can be added later through
extensions once extension compatibility matures, for example through official
Safari extensions.
