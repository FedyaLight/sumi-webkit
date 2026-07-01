import SwiftUI

/// Applies workspace themes to windows and drives interactive space-transition
/// theming through `WorkspaceThemeCoordinator`.
@MainActor
final class BrowserWorkspaceThemeTransitionOwner {
    struct Dependencies {
        let workspaceThemeCoordinator: @MainActor () -> WorkspaceThemeCoordinator?
        let activeWindowId: @MainActor () -> UUID?
        let allWindows: @MainActor () -> [BrowserWindowState]
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func updateWorkspaceTheme(
        for windowState: BrowserWindowState,
        to newTheme: WorkspaceTheme,
        animate: Bool
    ) {
        guard !windowState.isIncognito else { return }
        dependencies.workspaceThemeCoordinator()?.update(
            for: windowState,
            to: newTheme,
            animate: animate,
            isActiveWindow: dependencies.activeWindowId() == windowState.id
        )
    }

    func commitWorkspaceTheme(_ workspaceTheme: WorkspaceTheme, for windowState: BrowserWindowState) {
        dependencies.workspaceThemeCoordinator()?.restore(workspaceTheme, in: windowState)
    }

    @discardableResult
    func beginInteractiveSpaceTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        identity: SpaceTransitionIdentity? = nil,
        initialProgress: Double = 0,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        dependencies.workspaceThemeCoordinator()?.beginInteractiveTransition(
            from: sourceSpace,
            to: destinationSpace,
            identity: identity,
            initialProgress: initialProgress,
            in: windowState
        )
    }

    func updateInteractiveSpaceTransition(
        progress: Double,
        identity: SpaceTransitionIdentity? = nil,
        in windowState: BrowserWindowState
    ) {
        dependencies.workspaceThemeCoordinator()?.updateInteractiveTransition(
            progress: progress,
            identity: identity,
            in: windowState
        )
    }

    func cancelInteractiveSpaceTransition(
        identity: SpaceTransitionIdentity? = nil,
        in windowState: BrowserWindowState
    ) {
        dependencies.workspaceThemeCoordinator()?.cancelInteractiveTransition(
            in: windowState,
            identity: identity
        )
    }

    func finishInteractiveSpaceTransition(
        to destinationSpace: Space,
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity? = nil
    ) {
        dependencies.workspaceThemeCoordinator()?.finishInteractiveTransition(
            to: destinationSpace.workspaceTheme,
            in: windowState,
            identity: identity
        )
    }

    /// Manual workspace-theme sync for windows currently displaying this space.
    /// This is intentionally not part of the normal space-switch path.
    func syncWorkspaceThemeAcrossWindows(
        for space: Space,
        animate: Bool
    ) {
        for windowState in dependencies.allWindows() {
            guard !windowState.isIncognito else { continue }
            if windowState.currentSpaceId == space.id {
                guard !windowState.isInteractiveSpaceTransition else { continue }
                updateWorkspaceTheme(
                    for: windowState,
                    to: space.workspaceTheme,
                    animate: animate
                )
            }
        }
    }
}

extension BrowserWorkspaceThemeTransitionOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            workspaceThemeCoordinator: { [weak browserManager] in
                browserManager?.workspaceThemeCoordinator
            },
            activeWindowId: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow?.id
            },
            allWindows: { [weak browserManager] in
                guard let windowRegistry = browserManager?.windowRegistry else { return [] }
                return Array(windowRegistry.windows.values)
            }
        )
    }
}
