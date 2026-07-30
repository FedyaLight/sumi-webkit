import Foundation

extension RegularTabShortcutConversionService {
    static func compose(
        windows: ShortcutTabWindowQuery,
        regularTabs: RegularTabCollectionOwner,
        splitGroups: SplitGroupStore,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        resolution: ShortcutPinRuntimeResolutionOwner,
        transaction: RegularTabShortcutCommitTransaction
    ) -> Self {
        let structure = RegularTabShortcutStructureTransition(
            regularTabs: regularTabs,
            splitGroupStore: splitGroups,
            structuralLookup: structuralLookup
        )
        let planner = RegularTabShortcutConversionPlanner(
            windows: windows,
            structureTransition: structure,
            runtimeConnection: runtimeConnection
        )
        let candidates = RegularTabShortcutCandidatePreparer(
            planner: planner,
            authorizer: TabShortcutConversionAuthorizer(windows: windows),
            pinFactory: resolution
        )
        let sidebar = RegularTabShortcutSidebarConversionService(
            candidates: candidates,
            sidebarCandidates: RegularTabShortcutSidebarCandidatePreparer(
                conversions: candidates
            ),
            replacementValidator: ShortcutSidebarDropReplacementValidator(),
            transaction: transaction
        )
        return Self(
            candidates: candidates,
            sidebar: sidebar,
            transaction: transaction
        )
    }
}
