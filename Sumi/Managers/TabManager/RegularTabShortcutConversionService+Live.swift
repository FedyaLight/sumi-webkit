import Foundation

extension RegularTabShortcutConversionService {
    convenience init(tabManager: TabManager) {
        let windows = tabManager.shortcutTabWindowQuery
        let structure = RegularTabShortcutStructureTransition(
            regularTabs: tabManager.regularTabCollectionOwner,
            splitGroupStore: tabManager.splitGroupStore,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let planner = RegularTabShortcutConversionPlanner(
            windows: windows,
            structureTransition: structure,
            runtimeConnection: tabManager.runtimePortConnection
        )
        let candidates = RegularTabShortcutCandidatePreparer(
            planner: planner,
            authorizer: TabShortcutConversionAuthorizer(windows: windows),
            pinFactory: tabManager.shortcutPinRuntimeResolutionOwner
        )
        let transaction = RegularTabShortcutCommitTransaction(
            persistence: tabManager.structuralPersistence,
            pins: tabManager.shortcutPinStoreOwner,
            folderOpenState: tabManager.folderOpenState,
            splitMutations: tabManager.splitGroupMutations,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            structuralLookup: tabManager.structuralLookupCoordinator,
            liveShortcuts: tabManager.liveShortcutTabs,
            presentationResolution: tabManager.shortcutPinRuntimeResolutionOwner,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            displayedTransition: DisplayedTabShortcutConversionCommitter(
                materializer: tabManager.shortcutTabMaterializer,
                containerRemoval: tabManager.shortcutContainerRemovalOwner,
                adopter: ShortcutTabAdopter(tabManager: tabManager),
                regularTabs: tabManager.regularTabCollectionOwner,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            detachedTransition: DetachedTabShortcutConverter(tabManager: tabManager)
        )
        self.init(
            candidates: candidates,
            sidebarCandidates: RegularTabShortcutSidebarCandidatePreparer(
                conversions: candidates
            ),
            replacementValidator: ShortcutSidebarDropReplacementValidator(),
            transaction: transaction
        )
    }
}
