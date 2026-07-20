import Foundation
import SumiDomain

@MainActor
final class ShortcutPinReorderTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let essentialsVisualOrder: EssentialsVisualOrderTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        essentialsVisualOrder: EssentialsVisualOrderTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.essentialsVisualOrder = essentialsVisualOrder
    }

    func reorderEssential(_ pin: ShortcutPin, to index: Int) -> Bool {
        structuralLookup.withTransaction {
            guard self.pins.shortcutPin(by: pin.id) === pin else { return false }
            guard let profileID = pin.profileId else { return false }
            return essentialsVisualOrder.reorder(
                .shortcut(pin.id),
                for: profileID,
                to: index
            )
        }
    }

    func reorderSpacePinned(
        _ pin: ShortcutPin,
        in spaceID: UUID,
        to index: Int
    ) -> Bool {
        structuralLookup.withTransaction {
            guard self.pins.shortcutPin(by: pin.id) === pin else { return false }
            if pin.folderId == nil {
                return self.spacePinnedVisualOrder.reorder(
                    .shortcut(pin.id),
                    in: spaceID,
                    to: index
                )
            }

            var didReorder = false
            spacePinnedStructure.withSpacePinnedShortcutGroup(
                for: spaceID,
                folderId: pin.folderId
            ) { folderPins in
                guard let currentIndex = folderPins.firstIndex(where: {
                    $0 === pin
                }) else { return }
                let targetIndex = self.spacePinnedStructure
                    .adjustedSameContainerInsertionIndex(
                        currentIndex: currentIndex,
                        proposedIndex: index
                    )
                guard targetIndex != currentIndex else { return }
                folderPins.remove(at: currentIndex)
                folderPins.insert(
                    pin,
                    at: max(0, min(targetIndex, folderPins.count))
                )
                didReorder = true
            }
            if didReorder { structuralMutations.schedulePersistence() }
            return didReorder
        }
    }
}
