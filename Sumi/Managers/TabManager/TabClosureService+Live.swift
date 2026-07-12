import Foundation

extension TabClosureService {
    static func live(tabManager: TabManager) -> TabClosureService {
        compose(
            tabManager: tabManager,
            persistence: tabManager.structuralPersistence
        )
    }

    static func compose(
        tabManager: TabManager,
        persistence: any TabClosurePersistence
    ) -> TabClosureService {
        let candidateRetirement = TabClosureCandidateRetirement(
            shortcutRetirement: tabManager.shortcutLiveTabRetirement,
            persistence: persistence,
            transientTabs: tabManager.transientWebKitTabLifecycleOwner
        )
        let runtimeCleanup = RegularTabClosureRuntimeCleanup(
            membership: tabManager.tabCollectionMembershipOwner
        )
        return TabClosureService(
            transactions: tabManager.structuralLookupCoordinator,
            candidateRetirement: candidateRetirement,
            regularTabs: tabManager.regularTabCollectionOwner,
            spaces: tabManager.spaceStateOwner,
            selection: tabManager.selectionStateOwner,
            runtimeCleanup: runtimeCleanup,
            persistence: persistence,
            shortcutPresentation: tabManager.shortcutPresentationOwner,
            runtimePorts: tabManager.runtimePortConnection
        )
    }
}
