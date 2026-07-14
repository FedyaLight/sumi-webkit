import SumiDomain
import SwiftUI

/// Applies workspace themes to windows and drives interactive space-transition
/// theming through `WorkspaceThemeCoordinator`.
@MainActor
final class BrowserWorkspaceThemeTransitionOwner {
    private let shellRuntime: BrowserShellRuntime
    private let coordinator: WorkspaceThemeCoordinator

    init(
        shellRuntime: BrowserShellRuntime,
        coordinator: WorkspaceThemeCoordinator
    ) {
        self.shellRuntime = shellRuntime
        self.coordinator = coordinator
    }

    func updateWorkspaceTheme(
        for windowState: BrowserWindowState,
        to newTheme: WorkspaceTheme,
        animate: Bool
    ) {
        guard !windowState.isIncognito else { return }
        coordinator.update(
            for: windowState,
            to: newTheme,
            animate: animate,
            isActiveWindow: shellRuntime.windowRegistry?.activeWindow?.id == windowState.id
        )
    }

    func commitWorkspaceTheme(_ workspaceTheme: WorkspaceTheme, for windowState: BrowserWindowState) {
        coordinator.restore(workspaceTheme, in: windowState)
    }

    @discardableResult
    func beginInteractiveSpaceTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        identity: SpaceTransitionIdentity? = nil,
        initialProgress: Double = 0,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        coordinator.beginInteractiveTransition(
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
        coordinator.updateInteractiveTransition(
            progress: progress,
            identity: identity,
            in: windowState
        )
    }

    func cancelInteractiveSpaceTransition(
        identity: SpaceTransitionIdentity? = nil,
        in windowState: BrowserWindowState
    ) {
        coordinator.cancelInteractiveTransition(
            in: windowState,
            identity: identity
        )
    }

    func finishInteractiveSpaceTransition(
        to destinationSpace: Space,
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity? = nil
    ) {
        coordinator.finishInteractiveTransition(
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
        guard let windowRegistry = shellRuntime.windowRegistry else { return }
        for windowState in windowRegistry.windows.values {
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
