import Observation
import SwiftUI

@Observable
@MainActor
final class SpacesSidebarRuntimeOwner {
    struct Dependencies {
        let windowState: BrowserWindowState
        let browserContext: SidebarBrowserContext
        let dragState: SidebarDragState
        let settings: SumiSettingsService
        let allowsInteractiveWork: Bool
        let reduceMotion: Bool
    }

    private var transitionCoordinator = SpaceSidebarTransitionCoordinator()

    var transitionState: SpaceSidebarTransitionState {
        transitionCoordinator.transitionState
    }

    var transitionSnapshot: SpaceSidebarTransitionSnapshot? {
        transitionCoordinator.transitionSnapshot
    }

    func sourceOpacity(for travelProgress: Double) -> Double {
        transitionCoordinator.sourceOpacity(for: travelProgress)
    }

    func destinationOpacity(for travelProgress: Double) -> Double {
        transitionCoordinator.destinationOpacity(for: travelProgress)
    }

    func sourceOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.sourceOffsetX(width: width)
    }

    func destinationOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.destinationOffsetX(width: width)
    }

    func committedSpaceId(
        spaces: [Space],
        dependencies: Dependencies
    ) -> UUID? {
        transitionCoordinator.committedSpaceId(in: context(spaces: spaces, dependencies: dependencies))
    }

    func visualSelectedSpaceId(
        spaces: [Space],
        dependencies: Dependencies
    ) -> UUID? {
        transitionCoordinator.visualSelectedSpaceId(in: context(spaces: spaces, dependencies: dependencies))
    }

    func usesSharedPinnedGrid(
        sourceSpace: Space,
        destinationSpace: Space,
        dependencies: Dependencies
    ) -> Bool {
        transitionCoordinator.usesSharedPinnedGrid(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            context: context(spaces: dependencies.currentSpaces(), dependencies: dependencies)
        )
    }

    func space(
        for id: UUID?,
        spaces: [Space],
        dependencies: Dependencies
    ) -> Space? {
        transitionCoordinator.space(for: id, in: context(spaces: spaces, dependencies: dependencies))
    }

    func resolvedPageProfileId(
        for space: Space?,
        spaces: [Space],
        dependencies: Dependencies
    ) -> UUID? {
        transitionCoordinator.resolvedPageProfileId(
            for: space,
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    func handleSpacesCollectionChange(
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.handleSpacesCollectionChange(
            context(spaces: spaces, dependencies: dependencies)
        )
    }

    func handleCommittedSpaceChange(
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.handleCommittedSpaceChange(
            context(spaces: spaces, dependencies: dependencies)
        )
    }

    func handleTransitionProgressFrame(
        _ progress: Double,
        transitionIdentity: SpaceTransitionIdentity?,
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.handleTransitionProgressFrame(
            progress,
            transitionIdentity: transitionIdentity,
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    func handleSwipeEvent(
        _ event: SpaceSwipeGestureEvent,
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.handleSwipeEvent(
            event,
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    func switchSpace(
        to targetSpace: Space,
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.switchSpace(
            to: targetSpace,
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    func cancelLocalSpaceTransitionIfNeeded(
        spaces: [Space],
        dependencies: Dependencies,
        cancelTheme: Bool
    ) {
        transitionCoordinator.cancelLocalSpaceTransitionIfNeeded(
            context: context(spaces: spaces, dependencies: dependencies),
            cancelTheme: cancelTheme
        )
    }

    func refreshCommittedSidebarDragGeometryIfInteractive(
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.refreshCommittedSidebarDragGeometryIfInteractive(
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    func refreshCommittedSidebarDragGeometry(
        spaces: [Space],
        dependencies: Dependencies
    ) {
        transitionCoordinator.refreshCommittedSidebarDragGeometry(
            context: context(spaces: spaces, dependencies: dependencies)
        )
    }

    private func context(
        spaces: [Space],
        dependencies: Dependencies
    ) -> SpaceSidebarTransitionCoordinator.Context {
        let windowState = dependencies.windowState
        let browserContext = dependencies.browserContext
        return SpaceSidebarTransitionCoordinator.Context(
            spaces: spaces,
            currentSpaces: {
                windowState.isIncognito
                    ? windowState.ephemeralSpaces
                    : browserContext.tabManager.spaces
            },
            windowState: windowState,
            browserContext: browserContext,
            dragState: dependencies.dragState,
            settings: dependencies.settings,
            allowsInteractiveWork: dependencies.allowsInteractiveWork,
            reduceMotion: dependencies.reduceMotion
        )
    }
}

@MainActor
private extension SpacesSidebarRuntimeOwner.Dependencies {
    func currentSpaces() -> [Space] {
        windowState.isIncognito
            ? windowState.ephemeralSpaces
            : browserContext.tabManager.spaces
    }
}
