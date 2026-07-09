import Foundation

@MainActor
protocol TabWindowQueryPort {
    func windowState(for windowId: UUID) -> BrowserWindowState?
    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void)
    func forEachWindowState(_ body: (BrowserWindowState) -> Void)
    func updateTabVisibility()
    func validateWindowStates()
    func persistWindowSession(for windowState: BrowserWindowState)
    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool)
}

@MainActor
struct LiveTabWindowQueryPort: TabWindowQueryPort {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        browserManager?.windowRegistry?.windows[windowId]
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        let windows = browserManager?.windowRegistry?.windows.map { ($0.key, $0.value) } ?? []
        for (windowId, windowState) in windows {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        let windowStates = browserManager?.windowRegistry?.allWindows ?? []
        for windowState in windowStates {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        browserManager?.compositorManager.updateTabVisibility()
    }

    func validateWindowStates() {
        browserManager?.windowSessionBundle.spaceStateOwner.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        browserManager?.windowSessionBundle.activationOwner.persistWindowSession(for: windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        browserManager?.chromeBundle.workspaceThemeTransitionOwner.syncWorkspaceThemeAcrossWindows(
            for: space,
            animate: animate
        )
    }
}
