extension ProfileDeletionMigration {
    /// Builds deletion from the shared tab and Space transition authorities.
    @MainActor
    static func compose(
        policy: ProfileAssignmentPolicy,
        runtimeConnection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        tabTransitions: TabProfileTransitionService,
        spaceTransitions: SpaceProfileTransitionService,
        spaceTransitionLifecycle: SpaceProfileTransitionRepository,
        shortcutReferences: ShortcutProfileReferenceRetirementService,
        selection: ProfileSelectionCoordinator
    ) -> ProfileDeletionMigration {
        ProfileDeletionMigration(
            policy: policy,
            runtimeConnection: runtimeConnection,
            operations: ProfileDeletionOperationPlanner(
                spaces: spaces,
                policy: policy,
                tabTransitions: tabTransitions,
                spaceTransitions: spaceTransitions,
                spaceTransitionLifecycle: spaceTransitionLifecycle
            ),
            settlement: ProfileDeletionSettlementCoordinator(),
            finalizer: ProfileDeletionFinalizer(
                references: shortcutReferences,
                runtimeConnection: runtimeConnection,
                selection: selection
            )
        )
    }
}
