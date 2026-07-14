import Foundation
import SumiDomain

/// Commits the window-local Space/Profile context and its matching chrome
/// theme. Process-wide activation, tab handoff, and persistence remain outside
/// this service because they have different ownership and ordering rules.
@MainActor
final class BrowserWindowSpaceContextTransition {
    private let contextReconciler: BrowserWindowSpaceContextReconciler
    private let sanitizeFloatingBarState: (BrowserWindowState) -> Void
    private let syncShortcutSelectionState: (BrowserWindowState) -> Void
    private let updateWorkspaceTheme: (BrowserWindowState, WorkspaceTheme, Bool) -> Void
    private let finishInteractiveTransition: (
        Space,
        BrowserWindowState,
        SpaceTransitionIdentity
    ) -> Void

    init(
        contextReconciler: BrowserWindowSpaceContextReconciler,
        sanitizeFloatingBarState: @escaping (BrowserWindowState) -> Void,
        syncShortcutSelectionState: @escaping (BrowserWindowState) -> Void,
        updateWorkspaceTheme: @escaping (
            BrowserWindowState,
            WorkspaceTheme,
            Bool
        ) -> Void,
        finishInteractiveTransition: @escaping (
            Space,
            BrowserWindowState,
            SpaceTransitionIdentity
        ) -> Void
    ) {
        self.contextReconciler = contextReconciler
        self.sanitizeFloatingBarState = sanitizeFloatingBarState
        self.syncShortcutSelectionState = syncShortcutSelectionState
        self.updateWorkspaceTheme = updateWorkspaceTheme
        self.finishInteractiveTransition = finishInteractiveTransition
    }

    func sanitizePreservedSelection(in windowState: BrowserWindowState) {
        sanitizeFloatingBarState(windowState)
    }

    func completePreservedSelectionRefresh(in windowState: BrowserWindowState) {
        syncShortcutSelectionState(windowState)
    }

    func commitContext(
        _ space: Space,
        to windowState: BrowserWindowState
    ) {
        applyContext(space, to: windowState)
    }

    func completeVisualTransition(
        to space: Space,
        in windowState: BrowserWindowState,
        identity: SpaceTransitionIdentity?
    ) {
        if let identity {
            finishInteractiveTransition(space, windowState, identity)
        } else {
            updateWorkspaceTheme(windowState, space.workspaceTheme, true)
        }
    }

    private func applyContext(_ space: Space, to windowState: BrowserWindowState) {
        if windowState.currentSpaceId != space.id {
            windowState.currentSpaceId = space.id
        }
        if windowState.currentProfileId != space.profileId {
            windowState.currentProfileId = space.profileId
        }
        contextReconciler.synchronize(windowState)
    }
}
