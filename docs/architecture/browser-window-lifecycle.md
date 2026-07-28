# Browser window lifecycle

Sumi follows Zen's user-visible multi-window rules while keeping AppKit as the
native shell authority.

## Invariants

- `WindowRegistry` is the live identity map. A `BrowserWindowState` is
  published only after its `NSWindow` is bound, and `NSWindow.willClose` removes
  that exact pair once.
- Sumi's window-session archive is the only restoration owner. SwiftUI scene
  restoration is disabled so AppKit cannot resurrect a second, unrelated
  `WindowGroup` shell.
- The initial `WindowGroup` state receives its durable sidebar, theme,
  selection, and geometry projection before SwiftUI mounts the shell.
  Registration completes runtime restoration; it does not perform a second
  visible chrome projection.
- Normal windows share durable browser data but keep selection, sidebar,
  transient chrome, split focus, and WebView residence window-local.
- Incognito windows never enter the durable snapshot or recently-closed window
  history.
- A newly requested window has fresh window identity and native cascade
  placement. It does not inherit another window's frame or display mode.
- A restored or recently closed window keeps its archived frame and display
  mode. Invalid or off-screen frames are constrained to a currently available
  display. The frame is applied at most once to each native shell and the
  pending restore is consumed by one geometry policy.
- Moved standard buttons keep AppKit's native target/action. Programmatic
  closing uses `performClose:`. AppKit alone owns button action, enablement,
  localized accessibility labels, active-state dimming, and hover glyphs.
  Sumi owns only custody, layout, visibility, and interaction hit testing.
  Once `willClose` begins, the custodian stops moving live buttons back into
  the titlebar being torn down.
- Reopening the app from the Dock lets AppKit reveal an existing visible or
  miniaturized window. A new normal window is created only when no browser
  windows remain.
- One close notification owns persistence and registry teardown. SwiftUI view
  disappearance is not a second lifecycle signal.

## Module boundaries

- `BrowserWindowShellService` creates AppKit-owned secondary/private/restored
  shells. SwiftUI still creates the initial `WindowGroup` shell because scene
  ownership cannot be transferred to the service safely. Both adapters meet at
  the same deep seams: `WindowRegistry`, `BrowserWindowBridge`,
  `BrowserWindowGeometryPolicy`, and the native `willClose` transaction.
- `BrowserWindowGeometryPolicy` is the only AppKit geometry/display-mode
  adapter. Runtime presentation and extension projection read its canonical
  mode precedence: miniaturized, fullscreen, zoomed, normal.
- `WindowSessionPersistenceCoordinator` is the live persistence transaction.
  It builds the regular-window projection once, reuses it for the primary
  snapshot and archive, and cancels older coalesced writes that the transaction
  supersedes.
- `BrowserAppOrchestrationOwner` owns app-active/background and Dock-reopen
  behavior. `BrowserApplicationReopenPolicy` is the pure decision used by that
  owner; there is no forwarding controller.

## Zen parity map

| Scenario | Zen rule | Sumi owner |
| --- | --- | --- |
| `Cmd+N` | Clone shared browser/sidebar data, discard source geometry and selection | `BrowserWindowCommands` + `BrowserWindowGeometryPolicy` |
| Close second window | Mark closing state before synchronized teardown; avoid reentrant close work | native standard-button action + `BrowserWindowBridge` + traffic-light custodian |
| Restore closed window | Keep the closed window's own geometry and session selection | window-session snapshot/archive |
| Restart with multiple windows | Restore normal windows once; exclude private windows | `StartupWindowRestoreService` |
| Private window | Empty, isolated, non-durable shell | incognito branch of `BrowserWindowShellService` |
| Dock reopen after all windows close | Ensure a usable normal window exists | `BrowserAppOrchestrationOwner` + `BrowserApplicationReopenPolicy` |

## Runtime cost

- The window lifecycle has no polling or background timers. Work is triggered
  by commands, registry events, AppKit notifications, or persistence changes.
- Window-session debounce uses one timer for the process, not one timer per
  window. A burst performs one primary write and one archive projection.
- Sidebar controls read the bridge's per-window native display mode instead of
  subscribing each header to four global fullscreen notifications.
- Geometry-free identity checks use the catalog's read-only ID projection and
  do not serialize complete sessions.
- `NSHostingView` already supplies a transparent backing layer. Sumi keeps the
  required nonopaque `NSWindow` for behind-window material but does not repeat
  transparency mutations on the hosting content layer.
