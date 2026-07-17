import Foundation

@MainActor
protocol TabWindowQueryPort {
    func windowState(for windowId: UUID) -> BrowserWindowState?
    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void)
    func forEachWindowState(_ body: (BrowserWindowState) -> Void)
    func updateTabVisibility()
    func validateWindowStates() -> Set<UUID>
    func persistWindowSession(for windowState: BrowserWindowState)
    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool)
}

@MainActor
struct LiveTabWindowQueryPort: TabWindowQueryPort {
    private let shellRuntime: BrowserShellRuntime
    private let compositor: TabCompositorManager
    private let windowStateReconciler: BrowserWindowStateReconciler
    private let persistence: WindowSessionPersistenceCoordinator
    private let workspaceThemes: BrowserWorkspaceThemeTransitionOwner

    init(
        shellRuntime: BrowserShellRuntime,
        compositor: TabCompositorManager,
        windowStateReconciler: BrowserWindowStateReconciler,
        persistence: WindowSessionPersistenceCoordinator,
        workspaceThemes: BrowserWorkspaceThemeTransitionOwner
    ) {
        self.shellRuntime = shellRuntime
        self.compositor = compositor
        self.windowStateReconciler = windowStateReconciler
        self.persistence = persistence
        self.workspaceThemes = workspaceThemes
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        shellRuntime.windowRegistry.windows[windowId]
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        let windows = shellRuntime.windowRegistry.windows.map { ($0.key, $0.value) }
        for (windowId, windowState) in windows {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        let windowStates = shellRuntime.windowRegistry.allWindows
        for windowState in windowStates {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        compositor.updateTabVisibility()
    }

    func validateWindowStates() -> Set<UUID> {
        windowStateReconciler.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        workspaceThemes.syncWorkspaceThemeAcrossWindows(
            for: space,
            animate: animate
        )
    }
}
