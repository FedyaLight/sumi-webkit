import Foundation
import SumiDomain

@MainActor
final class BrowserSpaceTransitionRoutingOwner {
    private let splitFocus: SplitShortcutFocusService
    private let spaceTransitions: BrowserWindowSpaceTransitionService
    private let themeTransitions: BrowserWorkspaceThemeTransitionOwner

    init(
        splitFocus: SplitShortcutFocusService,
        spaceTransitions: BrowserWindowSpaceTransitionService,
        themeTransitions: BrowserWorkspaceThemeTransitionOwner
    ) {
        self.splitFocus = splitFocus
        self.spaceTransitions = spaceTransitions
        self.themeTransitions = themeTransitions
    }

    func completePendingSplitGroupFocusIfReady(
        in windowState: BrowserWindowState,
        spaceID: UUID
    ) {
        splitFocus.completePendingSplitGroupFocusIfReady(
            in: windowState,
            spaceId: spaceID
        )
    }

    func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {
        spaceTransitions.setActiveSpace(space, in: windowState)
    }

    func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        completing transition: SpaceTransitionIdentity
    ) {
        spaceTransitions.setActiveSpace(
            space,
            in: windowState,
            completingTransition: transition
        )
    }

    func previewWorkspaceTheme(
        _ theme: WorkspaceTheme,
        in windowState: BrowserWindowState
    ) {
        guard !windowState.isIncognito else { return }
        themeTransitions.commitWorkspaceTheme(theme, for: windowState)
    }

    func beginInteractiveSpaceTransition(
        from source: Space,
        to destination: Space,
        identity: SpaceTransitionIdentity,
        in windowState: BrowserWindowState
    ) -> SpaceTransitionIdentity? {
        themeTransitions.beginInteractiveSpaceTransition(
            from: source,
            to: destination,
            identity: identity,
            in: windowState
        )
    }

    func updateInteractiveSpaceTransition(
        progress: Double,
        identity: SpaceTransitionIdentity?,
        in windowState: BrowserWindowState
    ) {
        themeTransitions.updateInteractiveSpaceTransition(
            progress: progress,
            identity: identity,
            in: windowState
        )
    }

    func cancelInteractiveSpaceTransition(
        identity: SpaceTransitionIdentity?,
        in windowState: BrowserWindowState
    ) {
        themeTransitions.cancelInteractiveSpaceTransition(
            identity: identity,
            in: windowState
        )
    }
}
