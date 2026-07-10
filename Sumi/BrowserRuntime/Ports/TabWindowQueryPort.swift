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
    private let runtime: BrowserManagerRuntimeReference

    init(runtime: BrowserManagerRuntimeReference) {
        self.runtime = runtime
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        runtime.require().windowRegistry?.windows[windowId]
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        let windows = runtime.require().windowRegistry?.windows.map { ($0.key, $0.value) } ?? []
        for (windowId, windowState) in windows {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        let windowStates = runtime.require().windowRegistry?.allWindows ?? []
        for windowState in windowStates {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        runtime.require().compositorManager.updateTabVisibility()
    }

    func validateWindowStates() {
        runtime.require().windowSessionBundle.spaceStateOwner.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        runtime.require().windowSessionBundle.persistence.persist(windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        runtime.require().chromeBundle.workspaceThemeTransitionOwner.syncWorkspaceThemeAcrossWindows(
            for: space,
            animate: animate
        )
    }
}
