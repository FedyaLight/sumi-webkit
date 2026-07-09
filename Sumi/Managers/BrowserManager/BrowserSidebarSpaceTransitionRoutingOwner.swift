import Foundation

@MainActor
final class BrowserSpaceTransitionRoutingOwner {
    private let completePendingSplitGroupFocusIfReadyAction: @MainActor (BrowserWindowState, UUID) -> Void
    private let setActiveSpaceAction: @MainActor (Space, BrowserWindowState) -> Void
    private let setActiveSpaceFromTransitionAction: @MainActor (Space, BrowserWindowState, SpaceTransitionIdentity) -> Void
    private let beginInteractiveSpaceTransitionAction: @MainActor (
        Space,
        Space,
        SpaceTransitionIdentity,
        BrowserWindowState
    ) -> SpaceTransitionIdentity?
    private let updateInteractiveSpaceTransitionAction: @MainActor (Double, SpaceTransitionIdentity?, BrowserWindowState) -> Void
    private let cancelInteractiveSpaceTransitionAction: @MainActor (SpaceTransitionIdentity?, BrowserWindowState) -> Void

    init(
        completePendingSplitGroupFocusIfReady: @escaping @MainActor (BrowserWindowState, UUID) -> Void,
        setActiveSpace: @escaping @MainActor (Space, BrowserWindowState) -> Void,
        setActiveSpaceFromTransition: @escaping @MainActor (Space, BrowserWindowState, SpaceTransitionIdentity) -> Void,
        beginInteractiveSpaceTransition: @escaping @MainActor (
            Space,
            Space,
            SpaceTransitionIdentity,
            BrowserWindowState
        ) -> SpaceTransitionIdentity?,
        updateInteractiveSpaceTransition: @escaping @MainActor (Double, SpaceTransitionIdentity?, BrowserWindowState) -> Void,
        cancelInteractiveSpaceTransition: @escaping @MainActor (SpaceTransitionIdentity?, BrowserWindowState) -> Void
    ) {
        self.completePendingSplitGroupFocusIfReadyAction = completePendingSplitGroupFocusIfReady
        self.setActiveSpaceAction = setActiveSpace
        self.setActiveSpaceFromTransitionAction = setActiveSpaceFromTransition
        self.beginInteractiveSpaceTransitionAction = beginInteractiveSpaceTransition
        self.updateInteractiveSpaceTransitionAction = updateInteractiveSpaceTransition
        self.cancelInteractiveSpaceTransitionAction = cancelInteractiveSpaceTransition
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            completePendingSplitGroupFocusIfReady: { [weak browserManager] windowState, spaceId in
                browserManager?.sidebarCommandService.splitShortcutRouting.completePendingSplitGroupFocusIfReady(
                    in: windowState,
                    spaceId: spaceId
                )
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.windowSpaceStateOwner.setActiveSpace(space, in: windowState)
            },
            setActiveSpaceFromTransition: { [weak browserManager] space, windowState, identity in
                browserManager?.windowSpaceStateOwner.setActiveSpace(
                    space,
                    in: windowState,
                    completingTransition: identity
                )
            },
            beginInteractiveSpaceTransition: { [weak browserManager] source, destination, identity, windowState in
                browserManager?.workspaceThemeTransitionOwner.beginInteractiveSpaceTransition(
                    from: source,
                    to: destination,
                    identity: identity,
                    in: windowState
                )
            },
            updateInteractiveSpaceTransition: { [weak browserManager] progress, identity, windowState in
                browserManager?.workspaceThemeTransitionOwner.updateInteractiveSpaceTransition(
                    progress: progress,
                    identity: identity,
                    in: windowState
                )
            },
            cancelInteractiveSpaceTransition: { [weak browserManager] identity, windowState in
                browserManager?.workspaceThemeTransitionOwner.cancelInteractiveSpaceTransition(identity: identity, in: windowState)
            }
        )
    }

    func makeActions() -> SidebarSpaceTransitionActions {
        SidebarSpaceTransitionActions(
            completePendingSplitGroupFocusIfReady: { [weak self] windowState, spaceId in
                self?.completePendingSplitGroupFocusIfReadyAction(windowState, spaceId)
            },
            setActiveSpace: { [weak self] space, windowState in
                self?.setActiveSpaceAction(space, windowState)
            },
            setActiveSpaceFromTransition: { [weak self] space, windowState, identity in
                self?.setActiveSpaceFromTransitionAction(space, windowState, identity)
            },
            beginInteractiveSpaceTransition: { [weak self] source, destination, identity, windowState in
                self?.beginInteractiveSpaceTransitionAction(source, destination, identity, windowState)
            },
            updateInteractiveSpaceTransition: { [weak self] progress, identity, windowState in
                self?.updateInteractiveSpaceTransitionAction(progress, identity, windowState)
            },
            cancelInteractiveSpaceTransition: { [weak self] identity, windowState in
                self?.cancelInteractiveSpaceTransitionAction(identity, windowState)
            }
        )
    }
}
