import Combine
import Foundation

@MainActor
enum BrowserLastSessionMergeFactory {
    static func make(
        state: TabStateStore,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        structuralLookup: TabStructuralLookupCoordinator,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        membership: TabCollectionMembershipOwner,
        tabFactory: TabFactory,
        persistence: TabStructuralPersistenceService,
        lazyRestore: TabLazyRestoreCoordinator,
        changes: ObservableObjectPublisher
    ) -> TabLastSessionMergeMaterializer {
        TabLastSessionMergeMaterializer(
            planning: TabLastSessionMergePlanningService(
                planner: TabLastSessionMergePlanner(),
                snapshotter: TabLastSessionLiveStateSnapshotter(
                    spaces: state.spaces,
                    folders: state.folders,
                    shortcutPins: state.shortcutPins,
                    regularTabs: state.regularTabs
                )
            ),
            profileAdmission: TabLastSessionProfileAdmissionTransaction(
                ledger: profileAdmissions
            ),
            structuralLookup: structuralLookup,
            commitTransaction: TabLastSessionMergeCommitTransaction(
                spaces: TabLastSessionSpaceMaterializer(
                    spaces: state.spaces,
                    persistence: persistence,
                    changes: changes
                ),
                folders: TabLastSessionFolderMaterializer(
                    structuralMutations: structuralMutations
                ),
                shortcuts: TabLastSessionShortcutMaterializer(
                    structuralMutations: structuralMutations,
                    spacePinnedStructure: spacePinnedStructure
                ),
                regularTabs: TabLastSessionRegularTabMaterializer(
                    structuralMutations: structuralMutations,
                    membership: membership,
                    tabFactory: tabFactory
                ),
                selection: TabLastSessionSelectionMaterializer(
                    spaces: state.spaces,
                    selection: state.selection
                )
            ),
            settlement: TabLastSessionMergeSettlement(
                lazyRestore: lazyRestore,
                persistence: persistence
            )
        )
    }
}
