import Foundation

@MainActor
final class BrowserSpaceTransitionRoutingOwner {
    struct Dependencies {
        let completePendingSplitGroupFocusIfReady: @MainActor (BrowserWindowState, UUID) -> Void
        let setActiveSpace: @MainActor (Space, BrowserWindowState) -> Void
        let setActiveSpaceFromTransition: @MainActor (Space, BrowserWindowState, SpaceTransitionIdentity) -> Void
        let beginInteractiveSpaceTransition: @MainActor (
            Space,
            Space,
            SpaceTransitionIdentity,
            BrowserWindowState
        ) -> SpaceTransitionIdentity?
        let updateInteractiveSpaceTransition: @MainActor (Double, SpaceTransitionIdentity?, BrowserWindowState) -> Void
        let cancelInteractiveSpaceTransition: @MainActor (SpaceTransitionIdentity?, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func makeActions() -> SidebarSpaceTransitionActions {
        SidebarSpaceTransitionActions(
            completePendingSplitGroupFocusIfReady: { [weak self] windowState, spaceId in
                self?.dependencies.completePendingSplitGroupFocusIfReady(windowState, spaceId)
            },
            setActiveSpace: { [weak self] space, windowState in
                self?.dependencies.setActiveSpace(space, windowState)
            },
            setActiveSpaceFromTransition: { [weak self] space, windowState, identity in
                self?.dependencies.setActiveSpaceFromTransition(space, windowState, identity)
            },
            beginInteractiveSpaceTransition: { [weak self] source, destination, identity, windowState in
                self?.dependencies.beginInteractiveSpaceTransition(source, destination, identity, windowState)
            },
            updateInteractiveSpaceTransition: { [weak self] progress, identity, windowState in
                self?.dependencies.updateInteractiveSpaceTransition(progress, identity, windowState)
            },
            cancelInteractiveSpaceTransition: { [weak self] identity, windowState in
                self?.dependencies.cancelInteractiveSpaceTransition(identity, windowState)
            }
        )
    }
}

extension BrowserSpaceTransitionRoutingOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            completePendingSplitGroupFocusIfReady: { [weak browserManager] windowState, spaceId in
                browserManager?.sidebarCommandService.splitShortcutRouting.completePendingSplitGroupFocusIfReady(
                    in: windowState,
                    spaceId: spaceId
                )
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.setActiveSpace(space, in: windowState)
            },
            setActiveSpaceFromTransition: { [weak browserManager] space, windowState, identity in
                browserManager?.setActiveSpace(
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
}
