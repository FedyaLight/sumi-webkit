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

    func beginInteractiveTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        initialProgress: Double,
        in windowState: BrowserWindowState
    ) {
        guard !windowState.isIncognito else { return }

        if windowState.spaceTransitionSourceSpaceId == sourceSpace.id,
           windowState.spaceTransitionDestinationSpaceId == destinationSpace.id,
           windowState.isInteractiveSpaceTransition {
            updateInteractiveTransition(
                progress: initialProgress,
                in: windowState
            )
            return
        }

        windowState.windowThemeState.beginInteractive(
            sourceSpaceId: sourceSpace.id,
            destinationSpaceId: destinationSpace.id,
            from: sourceSpace.workspaceTheme,
            to: destinationSpace.workspaceTheme,
            initialProgress: initialProgress
        )
    }

    func updateInteractiveTransition(
        progress: Double,
        in windowState: BrowserWindowState
    ) {
        guard windowState.isInteractiveSpaceTransition else { return }
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

    func cancelInteractiveTransition(in windowState: BrowserWindowState) {
        guard windowState.isInteractiveSpaceTransition else { return }
        windowState.windowThemeState.cancel()
    }

    func finishInteractiveTransition(
        to destinationTheme: WorkspaceTheme,
        in windowState: BrowserWindowState
    ) {
        restore(destinationTheme, in: windowState)
    }
}
