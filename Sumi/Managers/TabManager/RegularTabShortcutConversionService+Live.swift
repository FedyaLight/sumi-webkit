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
        let transaction = RegularTabShortcutCommitTransaction.live(
            tabManager: tabManager
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
