import Foundation

extension ProfileAssignmentServices {
    @MainActor
    static func live(
        tabManager: TabManager,
        selectionContext: TabSelectionContextProjection
    ) -> ProfileAssignmentServices {
        let policy = ProfileAssignmentPolicy(
            runtimeConnection: tabManager.runtimePortConnection,
            spaces: tabManager.spaceStateOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            transientTabs: tabManager.transientTabRegistryOwner
        )
        let pendingInheritance = PendingTabProfileInheritance()
        let tabs = TabProfileTransitionService(
            runtimeConnection: tabManager.runtimePortConnection,
            policy: policy,
            pendingInheritance: pendingInheritance,
            publication: TabProfileTransitionPublication(
                spaces: tabManager.spaceStateOwner,
                membership: tabManager.tabCollectionMembershipOwner,
                persistence: tabManager.structuralPersistence,
                structuralLookup: tabManager.structuralLookupCoordinator
            )
        )
        let spaceMutations = SpaceProfileMutationService(
            spaces: tabManager.spaceStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            registry: tabManager.liveShortcutTabs,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: tabManager.runtimeTeardown,
            terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher(
                structuralLookup: tabManager.structuralLookupCoordinator,
                runtimeTeardown: tabManager.runtimeTeardown
            ),
            changes: tabManager.objectWillChange
        )
        let spaceAdmission = SpaceProfileTransitionAdmission(
            profileMutations: spaceMutations,
            tabCandidates: SpaceProfileTabCandidatePlanner(
                membership: tabManager.tabCollectionMembershipOwner,
                registry: tabManager.liveShortcutTabs,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            membership: tabManager.tabCollectionMembershipOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let spacePublication = SpaceProfileTransitionPublication(
            membership: tabManager.tabCollectionMembershipOwner,
            persistence: tabManager.structuralPersistence,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let spaceRepository = SpaceProfileTransitionRepository(
            spaces: tabManager.spaceStateOwner,
            pendingInheritance: pendingInheritance,
            publication: spacePublication
        )
        let spaces = SpaceProfileTransitionService(
            runtimeConnection: tabManager.runtimePortConnection,
            admission: spaceAdmission,
            repository: spaceRepository
        )
        let shortcuts = ShortcutExecutionProfileAssignmentService(
            tabManager: tabManager,
            policy: policy
        )
        let selection = ProfileSelectionCoordinator(
            selectionContext: selectionContext,
            selection: tabManager.selectionStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            persistence: tabManager.structuralPersistence
        )
        let deletionReferences = ShortcutProfileReferenceMutationApplicator(
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            spacePinnedStructure: tabManager.spacePinnedStructureOwner,
            persistence: tabManager.structuralPersistence,
            runtimeConnection: tabManager.runtimePortConnection
        )
        let deletion = ProfileDeletionMigration(
            policy: policy,
            runtimeConnection: tabManager.runtimePortConnection,
            operations: ProfileDeletionOperationPlanner(
                spaces: tabManager.spaceStateOwner,
                policy: policy,
                tabTransitions: tabs,
                spaceTransitions: spaces,
                spaceTransitionLifecycle: spaceRepository
            ),
            settlement: ProfileDeletionSettlementCoordinator(),
            finalizer: ProfileDeletionFinalizer(
                pins: tabManager.shortcutPinCollectionStateOwner,
                references: deletionReferences,
                runtimeConnection: tabManager.runtimePortConnection,
                selection: selection
            )
        )
        return ProfileAssignmentServices(
            policy: policy,
            tabs: tabs,
            spaces: spaces,
            spaceLifecycle: spaceRepository,
            spaceAvailability: spacePublication,
            shortcuts: shortcuts,
            selection: selection,
            deletion: deletion
        )
    }
}
