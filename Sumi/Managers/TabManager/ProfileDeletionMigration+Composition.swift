extension ProfileDeletionMigration {
    /// Builds deletion from the shared tab and Space transition authorities.
    @MainActor
    static func compose(
        policy: ProfileAssignmentPolicy,
        runtimeConnection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        tabTransitions: TabProfileTransitionService,
        spaceTransitionLifecycle: SpaceProfileTransitionRepository,
        spaceCatalog: SpaceCatalogCommands,
        spaceRemoval: SpaceRemovalService,
        shortcutReferences: ShortcutProfileReferenceRetirementService,
        selection: ProfileSelectionCoordinator
    ) -> ProfileDeletionMigration {
        ProfileDeletionMigration(
            policy: policy,
            runtimeConnection: runtimeConnection,
            spaces: ProfileSpaceRetirementService(
                spaces: spaces,
                catalog: spaceCatalog,
                removal: spaceRemoval,
                transitions: spaceTransitionLifecycle
            ),
            operations: ProfileDeletionOperationPlanner(
                policy: policy,
                tabTransitions: tabTransitions
            ),
            settlement: ProfileDeletionSettlementCoordinator(),
            shortcutReferences: shortcutReferences,
            selection: selection
        )
    }
}
