import Foundation

extension ProfileAssignmentServices {
    @MainActor
    static func live(
        tabManager: TabManager,
        selectionContext: TabSelectionContextProjection
    ) -> ProfileAssignmentServices {
        let policy = ProfileAssignmentPolicy(tabManager: tabManager)
        let pendingInheritance = PendingTabProfileInheritance()
        let tabs = TabProfileTransitionService(
            tabManager: tabManager,
            policy: policy,
            pendingInheritance: pendingInheritance
        )
        let spaceMutations = SpaceProfileMutationService(tabManager: tabManager)
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
        let deletion = ProfileDeletionMigration(
            tabManager: tabManager,
            policy: policy,
            tabTransitions: tabs,
            spaceTransitions: spaces,
            spaceTransitionLifecycle: spaceRepository,
            selection: selection
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
