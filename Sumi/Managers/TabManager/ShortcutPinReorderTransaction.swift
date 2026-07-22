import Foundation
import SumiDomain

@MainActor
final class ShortcutPinReorderTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let essentialsVisualOrder: EssentialsVisualOrderTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        essentialsVisualOrder: EssentialsVisualOrderTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.pins = pins
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
            return self.spacePinnedVisualOrder.reorder(
                .shortcut(pin.id),
                in: spaceID,
                folderID: pin.folderId,
                to: index
            )
        }
    }
}
