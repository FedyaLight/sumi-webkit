import Foundation

@MainActor
final class TabLastSessionShortcutMaterializer {
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner

    init(
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner
    ) {
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
    }

    func materialize(_ plan: TabLastSessionMergePlan) {
        for profileID in plan.favoritePinsByProfile.keys.sorted(by: uuidOrder) {
            let pins = (plan.favoritePinsByProfile[profileID] ?? [])
                .enumerated().map {
                    makeShortcut(from: $0.element, index: $0.offset)
                }
            structuralMutations.setPinnedTabs(pins, for: profileID)
        }
        for spaceID in plan.orderedSpaceIds {
            let pins = (plan.spacePinnedShortcuts[spaceID] ?? []).map {
                makeShortcut(from: $0, index: $0.index)
            }
            structuralMutations.setSpacePinnedShortcuts(
                spacePinnedStructure.normalizedSpacePinnedShortcuts(pins),
                for: spaceID
            )
        }
    }

    private func makeShortcut(
        from descriptor: TabLastSessionShortcutDescriptor,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: descriptor.id,
            role: descriptor.kind == .favorite ? .favorite : .spacePinned,
            profileId: descriptor.profileId,
            executionProfileId: descriptor.executionProfileId,
            spaceId: descriptor.spaceId,
            index: index,
            folderId: descriptor.folderId,
            launchURL: descriptor.launchURL,
            title: descriptor.title,
            iconAsset: descriptor.iconAsset,
            titleIsCustom: descriptor.titleIsCustom
        )
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
