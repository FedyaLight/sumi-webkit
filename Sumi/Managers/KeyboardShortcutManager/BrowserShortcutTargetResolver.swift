import AppKit

/// Immutable target captured once at the AppKit command boundary.
/// Domain dispatchers must use this context instead of resolving active state
/// again while a command is in flight.
@MainActor
struct BrowserShortcutContext {
    let windowState: BrowserWindowState
    let appKitWindow: NSWindow
    let page: ActivePageResolution?
}

enum BrowserShortcutTarget {
    case browser(BrowserShortcutContext)
    case foreignWindow(NSWindow)
    case none
}

@MainActor
final class BrowserShortcutTargetResolver {
    private let windows: WindowRegistry
    private let pages: ActivePageResolver

    init(
        windows: WindowRegistry,
        pages: ActivePageResolver
    ) {
        self.windows = windows
        self.pages = pages
    }

    func resolve(keyWindow: NSWindow?) -> BrowserShortcutTarget {
        guard let keyWindow else { return .none }
        guard let windowState = windows.windowState(
            forAppKitWindow: keyWindow
        ) else { return .foreignWindow(keyWindow) }
        return .browser(
            BrowserShortcutContext(
                windowState: windowState,
                appKitWindow: keyWindow,
                page: pages.resolve(in: windowState)
            )
        )
    }
}
