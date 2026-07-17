import Foundation
import SumiDomain

/// Commits the window-local Space/Profile context and its matching chrome
/// theme. Process-wide activation, tab handoff, and persistence remain outside
/// this service because they have different ownership and ordering rules.
@MainActor
final class BrowserWindowSpaceContextTransition {
    private let contextReconciler: BrowserWindowSpaceContextReconciler
    private let floatingBar: FloatingBarPresentationService
    private let selection: BrowserTabSelectionOwner
    private let workspaceThemes: BrowserWorkspaceThemeTransitionOwner

    init(
        contextReconciler: BrowserWindowSpaceContextReconciler,
        floatingBar: FloatingBarPresentationService,
        selection: BrowserTabSelectionOwner,
        workspaceThemes: BrowserWorkspaceThemeTransitionOwner
    ) {
        self.contextReconciler = contextReconciler
        self.floatingBar = floatingBar
        self.selection = selection
        self.workspaceThemes = workspaceThemes
    }

    func sanitizePreservedSelection(in windowState: BrowserWindowState) {
        floatingBar.sanitize(in: windowState)
    }

    func completePreservedSelectionRefresh(in windowState: BrowserWindowState) {
        selection.syncShortcutSelectionState(for: windowState)
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
            workspaceThemes.finishInteractiveSpaceTransition(
                to: space,
                in: windowState,
                identity: identity
            )
        } else {
            workspaceThemes.updateWorkspaceTheme(
                for: windowState,
                to: space.workspaceTheme,
                animate: true
            )
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
