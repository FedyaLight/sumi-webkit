import SwiftUI

private enum WorkspaceThemeTransitionUpdatePolicy {
    /// Keeps sub-pixel trackpad noise from invalidating the whole themed chrome tree.
    static let interactiveProgressEpsilon = 0.0025
}

@MainActor
final class WorkspaceThemeCoordinator {
    func restore(
        _ theme: WorkspaceTheme,
        in windowState: BrowserWindowState
    ) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            windowState.windowThemeState.restore(theme)
        }
    }

    func update(
        for windowState: BrowserWindowState,
        to newTheme: WorkspaceTheme,
        animate: Bool,
        isActiveWindow: Bool
    ) {
        guard !windowState.isIncognito else { return }

        let currentTheme = windowState.displayedWorkspaceTheme
        let duration = 0.10

        guard animate, isActiveWindow, !currentTheme.visuallyEquals(newTheme) else {
            restore(newTheme, in: windowState)
            return
        }

        let token = UUID()
        windowState.windowThemeState.beginProgrammatic(
            from: currentTheme,
            to: newTheme,
            token: token
        )

        withAnimation(.easeInOut(duration: duration)) {
            windowState.windowThemeState.updateProgress(1.0)
        }

        Task { @MainActor [weak windowState] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.03) * 1_000_000_000))
            guard let windowState else { return }
            guard windowState.themeTransitionToken == token else { return }
            self.restore(newTheme, in: windowState)
        }
    }

    @discardableResult
    func beginInteractiveTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        identity requestedIdentity: SpaceTransitionIdentity? = nil,
        initialProgress: Double,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        guard !windowState.isIncognito else { return nil }

        if windowState.spaceTransitionSourceSpaceId == sourceSpace.id,
           windowState.spaceTransitionDestinationSpaceId == destinationSpace.id,
           windowState.isInteractiveSpaceTransition {
            guard requestedIdentity == nil || windowState.interactiveSpaceTransitionIdentity == requestedIdentity else {
                return beginNewInteractiveTransition(
                    from: sourceSpace,
                    to: destinationSpace,
                    identity: requestedIdentity,
                    initialProgress: initialProgress,
                    in: windowState
                )
            }
            updateInteractiveTransition(
                progress: initialProgress,
                identity: requestedIdentity,
                in: windowState
            )
            return windowState.interactiveSpaceTransitionIdentity ?? requestedIdentity
        }

        return beginNewInteractiveTransition(
            from: sourceSpace,
            to: destinationSpace,
            identity: requestedIdentity,
            initialProgress: initialProgress,
            in: windowState
        )
    }

    func updateInteractiveTransition(
        progress: Double,
        identity: SpaceTransitionIdentity? = nil,
        in windowState: BrowserWindowState
    ) {
        guard windowState.isInteractiveSpaceTransition else { return }
        guard windowState.windowThemeState.matchesInteractiveSpaceTransition(identity) else { return }
        let clampedProgress = min(max(progress, 0.0), 1.0)
        guard clampedProgress == 0.0
            || clampedProgress == 1.0
            || abs(windowState.themeTransitionProgress - clampedProgress)
                >= WorkspaceThemeTransitionUpdatePolicy.interactiveProgressEpsilon
        else {
            return
        }

        windowState.windowThemeState.updateProgress(clampedProgress)
    }

    func cancelInteractiveTransition(
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity? = nil
    ) {
        guard windowState.isInteractiveSpaceTransition else { return }
        guard windowState.windowThemeState.matchesInteractiveSpaceTransition(identity) else { return }
        windowState.windowThemeState.cancel()
    }

    func finishInteractiveTransition(
        to destinationTheme: WorkspaceTheme,
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity? = nil
    ) {
        guard windowState.isInteractiveSpaceTransition else { return }
        guard windowState.windowThemeState.matchesInteractiveSpaceTransition(identity) else { return }
        restore(destinationTheme, in: windowState)
    }

    private func beginNewInteractiveTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        identity requestedIdentity: SpaceTransitionIdentity?,
        initialProgress: Double,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        let identity = requestedIdentity ?? SpaceTransitionIdentity(
            sourceSpaceId: sourceSpace.id,
            destinationSpaceId: destinationSpace.id
        )
        guard identity.sourceSpaceId == sourceSpace.id,
              identity.destinationSpaceId == destinationSpace.id else {
            return nil
        }

        return windowState.windowThemeState.beginInteractive(
            identity: identity,
            from: sourceSpace.workspaceTheme,
            to: destinationSpace.workspaceTheme,
            initialProgress: initialProgress
        )
    }
}
