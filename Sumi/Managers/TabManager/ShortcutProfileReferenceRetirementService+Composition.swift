extension ShortcutProfileReferenceRetirementService {
    /// Builds the shortcut-reference mutation boundary used by retirement.
    @MainActor
    static func compose(
        pins: ShortcutPinCollectionStateOwner,
        splitGroups: SplitGroupStore,
        pendingPins: PendingShortcutPinAdopter,
        splitMutations: SplitGroupMutationService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        runtimeConnection: TabRuntimePortConnection,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) -> ShortcutProfileReferenceRetirementService {
        let mutations = ShortcutProfileReferenceMutationApplicator(
            structure: ShortcutProfileReferenceStructureMutation(
                pendingPins: pendingPins,
                structuralMutations: structuralMutations,
                spacePinnedStructure: spacePinnedStructure
            ),
            topology: ShortcutProfileReferenceTopologyMutation(
                splitGroups: splitGroups,
                splitMutations: splitMutations
            ),
            runtimeConnection: runtimeConnection,
            profileReferenceAdmission: profileReferenceAdmission
        )
        return ShortcutProfileReferenceRetirementService(
            pins: pins,
            splitGroups: splitGroups,
            pendingPins: pendingPins,
            mutations: mutations,
            profileReferenceAdmission: profileReferenceAdmission
        )
    }
}
