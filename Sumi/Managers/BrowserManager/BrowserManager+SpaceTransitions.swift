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

    func beginInteractiveSpaceTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        initialProgress: Double = 0,
        in windowState: BrowserWindowState
    ) {
        workspaceThemeCoordinator.beginInteractiveTransition(
            from: sourceSpace,
            to: destinationSpace,
            initialProgress: initialProgress,
            in: windowState
        )
    }

    func updateInteractiveSpaceTransition(progress: Double, in windowState: BrowserWindowState) {
        workspaceThemeCoordinator.updateInteractiveTransition(
            progress: progress,
            in: windowState
        )
    }

    func cancelInteractiveSpaceTransition(in windowState: BrowserWindowState) {
        workspaceThemeCoordinator.cancelInteractiveTransition(in: windowState)
    }

    func finishInteractiveSpaceTransition(
        to destinationSpace: Space,
        in windowState: BrowserWindowState
    ) {
        workspaceThemeCoordinator.finishInteractiveTransition(
            to: destinationSpace.workspaceTheme,
            in: windowState
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
