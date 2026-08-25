# Command Palette

The Command Palette is Sumi's window-local entry point for navigation and
browser actions. Arc is the interaction and visual reference. Zen is useful
for its readable action inventory and search-provider behavior. Neither
browser defines Sumi's internal architecture.

The implementation has two non-negotiable properties:

- results and commits belong to the window that opened the palette;
- SwiftUI renders immutable rows and never owns browser state.

## Ownership

| Module | Owns | Does not own |
| --- | --- | --- |
| `CommandPaletteSearchSessionOwner` | Query, mode, result publication, semantic selection, async search lifetime | Native responder state, browser mutation |
| `CommandPaletteNativeInteraction` | First responder, AppKit event monitor, deferred input, outside clicks, terminal commit latch | Search, ranking, command availability |
| `CommandPaletteNavigationTargetCatalog` | Window-local projection of tabs, launchers, and split groups | Activation, live UI state |
| `CommandPaletteBrowserContext` | Exact-window capabilities used at commit time | Palette presentation state |
| `CommandPaletteView` | Layout, material, hover, scrolling, and dispatching user intent | Search lifecycle, result identity, browser commands |

`BrowserURLBarBundle` constructs these modules with authorities already owned by
the window. Palette code must not discover a `BrowserManager` or fall back to
the current key window.

## Data flow

1. Opening the palette creates a session tied to one browser window.
2. Input is delivered through `CommandPaletteNativeInteraction`.
3. The session publishes local results immediately and starts the cancellable
   `SearchManager` request when needed.
4. Local and asynchronous results are merged into `[CommandPaletteRow]`.
5. SwiftUI renders that immutable snapshot.
6. Return or click produces a semantic commit intent.
7. `CommandPaletteBrowserContext` resolves the intent against the originating
   window and performs the mutation.

The palette is dismissed only after the commit path accepts the operation. An
action that replaces the palette, such as an empty split picker, starts a fresh
native interaction generation.

## Row model and identity

`CommandPaletteRow` is the only result model passed to SwiftUI. It contains:

- a semantic ID;
- immutable text, icon, accessory, and accessibility presentation;
- an activation identity;
- an optional semantic secondary action.

It does not contain a `Tab`, `BrowserManager`, command closure, or observable
store.

IDs describe browser meaning rather than list position:

- regular tabs use their tab UUID;
- launchers use `shortcut(pinID)` whether loaded or unloaded;
- split groups use `splitGroup(groupID)`;
- commands, Spaces, extensions, history entries, and bookmarks use their own
  durable identities.

This lets a result survive reordering or an asynchronous refresh without
losing selection. If the selected ID disappears, the session selects the first
remaining row in the same publication that installs the new result snapshot.

## Modes

The session has one mode at a time:

- `Everything` combines navigation, contextual actions, tabs, history,
  bookmarks, Spaces, extensions, and web suggestions.
- `Actions` searches the browser action catalog. Tab enters it only from an
  empty `Everything` query when no site-search offer is active.
- `Site Search` scopes navigation to one accepted search engine.

Escape leaves `Actions` or `Site Search` before dismissing the palette.
Backspace on an empty site-search query returns to `Everything`.

An empty `Everything` query shows contextual local results. There is no
separate Compact or Top Links palette mode.

## Result publication

For a typed query the session builds results in this order:

1. direct URL navigation;
2. matching local actions, Spaces, extensions, and durable navigation targets;
3. tabs, history, bookmarks, and remote suggestions from `SearchManager`.

The current search query is not repeated as a suggestion. Return commits the
input unless the user explicitly selects another row.

Local work is synchronous. Remote work is debounced and cancellable.

When the query changes, the session keeps the last settled provider rows on
screen until the new provider generation settles. New direct and local rows
are still published immediately ahead of them. This prevents blank frames
without allowing the old request to publish into the new generation.

Every provider publication carries its normalized source query. Completion
settles the current generation even when it contains no additional results.
Panel height changes only after both debounce and provider loading have
settled.

Action matching and ordering are deterministic. The ordered action template
lives in `CommandPaletteCommandSuggestionProvider` and is locked by tests; do
not duplicate it in this document or derive it from enum declaration order.

## Navigation targets

`CommandPaletteNavigationTargetCatalog` creates one projection for a query
generation.

Regular tabs remain runtime targets. Launchers and split groups retain their
durable identity even when their live tabs are unloaded. Live tabs may improve
the title or favicon in the snapshot, but never replace that identity.

A split group is represented by one row rather than one row per member:

- its title lists member titles in group order;
- its accessory is `Switch to Split View`;
- its icon uses `SplitTileGeometry`, shared with the Favorite split tile;
- grouped tabs and launchers are suppressed from the standalone result list.

Launcher results use `Switch to Tab`. Closing an active launcher is presented
as `Unload`; the runtime is retired while the durable pin remains.

Pinning, unpinning, Favorite changes, and split conversion call the same
structural transactions used by the sidebar. The palette must not reproduce
those mutations.

## Browser actions

Keyboard shortcuts and the palette share one command authority:

```swift
func canPerform(_ action: ShortcutAction, keyWindow: NSWindow?) -> Bool
func commandPaletteActionPresentations(
    keyWindow: NSWindow?
) -> [CommandPaletteBrowserActionPresentation]
func perform(_ action: ShortcutAction, keyWindow: NSWindow?) -> Bool
func performFromCommandPalette(
    _ action: ShortcutAction,
    keyWindow: NSWindow?
) -> CommandPaletteShortcutExecutionOutcome?
```

Command title, keywords, symbol, shortcut, availability, and execution route
stay together. The palette does not maintain a second command enum or its own
disabled-state rules.

Availability is checked when results are built and again immediately before
execution. A rejected action leaves the palette open and refreshes the
snapshot.

Spaces and extensions follow the same rule: the row stores a durable ID, while
commit delegates to the existing window-local execution path.

## Interaction rules

- The text field remains first responder while the result list is scrolled or
  navigated.
- Typing or changing mode returns the result list to the top.
- Keyboard selection and hover are independent. Hover never changes what
  Return commits.
- A result revision preserves selection by semantic ID.
- One interaction generation accepts at most one terminal commit.
- A lost originating window ends the session. It never retargets another
  window.
- The vertical scroll indicator is hidden, but wheel, trackpad, keyboard, and
  accessibility scrolling remain available.

Native focus and click behavior belongs in `CommandPaletteNativeInteraction`,
not in delayed SwiftUI callbacks.

## Rendering

`CommandPaletteLayoutPolicy`, `CommandPaletteMotionPolicy`, and theme tokens
are the source of truth for dimensions, animation, and color. Keep numeric
layout values out of result providers and catalogs.

The result list uses one row view for every `CommandPaletteRow`. Icons and
accessories may vary, but result kinds do not get separate list ownership.
Selected foreground is chosen for contrast against the current workspace
accent; hover uses a quieter surface tint.

Site Search confirmation animation is isolated from the result list and uses
compositor-friendly effects. Reduced Motion and Reduced Transparency preserve
layout and hit testing.

## Performance

The closed palette has no event monitor, observer, timer, provider task, or
favicon prefetch work.

While open:

- one cancellable debounce controls web suggestions;
- fuzzy matching and result merging run when the session snapshot changes, not
  from SwiftUI `body`;
- stale provider generations cannot publish;
- only visible rows request favicons;
- split icon layout is bounded by `SplitGroup.maximumMembers`;
- scroll and hover updates do not rebuild search results.

Do not add polling or a global result store. If a new source needs asynchronous
work, it must participate in the session generation and cancellation model.

## Tests

The main test surfaces are:

- `CommandPaletteSearchSessionOwnerTests` for modes, ordering, continuity, and
  semantic selection;
- `CommandPaletteNativeInteractionTests` for focus lifetime, replacement, and
  the commit latch;
- `CommandPaletteNavigationTargetCatalogTests` for durable tab, launcher, and
  split projection;
- browser shortcut router tests for shared availability and execution;
- `SumiCommandPaletteFocusUITests` for focus, scrolling, Site Search, launcher
  unload, split commands, and split result presentation;
- `FavoriteSplitCompactLayoutTests` for the split geometry shared with the
  palette.

Visual release checks should cover light and dark themes, Reduced Motion,
Reduced Transparency, empty and typed queries, keyboard selection, Actions,
Site Search, split results, and continuous typing without blank result frames.
