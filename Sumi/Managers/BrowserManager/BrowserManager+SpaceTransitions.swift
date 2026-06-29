import SwiftUI

@MainActor
extension BrowserManager {
    func updateWorkspaceTheme(
        for windowState: BrowserWindowState,
        to newTheme: WorkspaceTheme,
        animate: Bool
    ) {
        guard !windowState.isIncognito else { return }
        workspaceThemeCoordinator.update(
            for: windowState,
            to: newTheme,
            animate: animate,
            isActiveWindow: windowRegistry?.activeWindow?.id == windowState.id
        )
    }

    func commitWorkspaceTheme(_ workspaceTheme: WorkspaceTheme, for windowState: BrowserWindowState) {
        workspaceThemeCoordinator.restore(workspaceTheme, in: windowState)
    }

    @discardableResult
    func beginInteractiveSpaceTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        identity: SpaceTransitionIdentity? = nil,
        initialProgress: Double = 0,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        workspaceThemeCoordinator.beginInteractiveTransition(
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
        workspaceThemeCoordinator.updateInteractiveTransition(
            progress: progress,
            identity: identity,
            in: windowState
        )
    }

    func cancelInteractiveSpaceTransition(
        identity: SpaceTransitionIdentity? = nil,
        in windowState: BrowserWindowState
    ) {
        workspaceThemeCoordinator.cancelInteractiveTransition(in: windowState, identity: identity)
    }

    func finishInteractiveSpaceTransition(
        to destinationSpace: Space,
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity? = nil
    ) {
        workspaceThemeCoordinator.finishInteractiveTransition(
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
        guard let windowRegistry else { return }

        for (_, windowState) in windowRegistry.windows {
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
