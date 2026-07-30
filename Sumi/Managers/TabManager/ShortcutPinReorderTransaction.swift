import Foundation
import SumiDomain

@MainActor
final class ShortcutPinReorderTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let essentialsVisualOrder: EssentialsVisualOrderTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        essentialsVisualOrder: EssentialsVisualOrderTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.pins = pins
        self.runtimeConnection = runtimeConnection
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
            guard let folderID = pin.folderId,
                  self.runtimeConnection.current?.isLiveFolder(folderID) == true
            else {
                return self.spacePinnedVisualOrder.reorder(
                    .shortcut(pin.id),
                    in: spaceID,
                    folderID: pin.folderId,
                    to: index
                )
            }
            guard self.spacePinnedVisualOrder.reorder(
                .shortcut(pin.id),
                in: spaceID,
                folderID: folderID,
                to: index
            ) else { return false }
            guard let targetIndex = self.pins.folderPinnedPins(
                for: folderID,
                in: spaceID
            ).firstIndex(where: { $0.id == pin.id }) else {
                return true
            }
            self.runtimeConnection.current?.reconcileLiveFolderItemMove(
                shortcutPinID: pin.id,
                fromFolderID: folderID,
                toFolderID: folderID,
                targetIndex: targetIndex
            )
            return true
        }
    }
}
