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
            policy: policy,
            profileMutations: spaceMutations,
            tabCandidates: SpaceProfileTabCandidatePlanner(
                membership: tabManager.tabCollectionMembershipOwner,
                registry: tabManager.liveShortcutTabs,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            membership: tabManager.tabCollectionMembershipOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let spaces = SpaceProfileTransitionService(
            tabManager: tabManager,
            pendingInheritance: pendingInheritance,
            admission: spaceAdmission
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
            selection: selection
        )
        return ProfileAssignmentServices(
            policy: policy,
            tabs: tabs,
            spaces: spaces,
            shortcuts: shortcuts,
            selection: selection,
            deletion: deletion
        )
    }
}
