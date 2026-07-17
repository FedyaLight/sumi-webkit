import Combine

extension SpaceProfileTransitionService {
    /// Builds the Space-profile transaction graph once at the composition root.
    @MainActor
    static func compose(
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService,
        structuralLookup: TabStructuralLookupCoordinator,
        membership: TabCollectionMembershipOwner,
        persistence: TabStructuralPersistenceService,
        pendingInheritance: PendingTabProfileInheritance,
        changes: ObservableObjectPublisher
    ) -> (
        service: SpaceProfileTransitionService,
        lifecycle: SpaceProfileTransitionRepository,
        availability: SpaceProfileTransitionPublication
    ) {
        let mutations = SpaceProfileMutationService(
            spaces: spaces,
            runtimeConnection: runtimeConnection,
            transitions: SpaceProfilePresentationTransitionFactory(
                pins: pins,
                registry: registry,
                runtimeConnection: runtimeConnection,
                runtimeTeardown: runtimeTeardown,
                terminalPublisher:
                    SpaceProfilePresentationTerminalEffectPublisher(
                        structuralLookup: structuralLookup,
                        runtimeTeardown: runtimeTeardown
                    )
            ),
            changes: changes
        )
        let admission = SpaceProfileTransitionAdmission(
            profileMutations: mutations,
            tabCandidates: SpaceProfileTabCandidatePlanner(
                membership: membership,
                registry: registry,
                pins: pins
            ),
            membership: membership,
            structuralLookup: structuralLookup
        )
        let availability = SpaceProfileTransitionPublication(
            membership: membership,
            persistence: persistence,
            structuralLookup: structuralLookup
        )
        let lifecycle = SpaceProfileTransitionRepository(
            spaces: spaces,
            pendingInheritance: pendingInheritance,
            publication: availability
        )
        return (
            service: SpaceProfileTransitionService(
                runtimeConnection: runtimeConnection,
                admission: admission,
                repository: lifecycle
            ),
            lifecycle: lifecycle,
            availability: availability
        )
    }
}
