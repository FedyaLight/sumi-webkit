import Foundation

@MainActor
final class SidebarPinPlacementCommands {
    private let pins: ShortcutPinCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let structure: SpacePinnedStructureOwner
    private let placement: ShortcutPinPlacementCommandService

    init(
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        structure: SpacePinnedStructureOwner,
        placement: ShortcutPinPlacementCommandService
    ) {
        self.pins = pins
        self.folders = folders
        self.structure = structure
        self.placement = placement
    }

    func move(_ pin: ShortcutPin, toFolder folderID: UUID) -> Bool {
        guard let pin = current(pin),
              let folder = folders.folder(by: folderID) else { return false }
        let index = pins.folderPinnedPins(for: folderID, in: folder.spaceId).count
        return placement.move(
            pin,
            to: .spacePinned,
            profileId: nil,
            spaceId: folder.spaceId,
            folderId: folderID,
            index: index,
            openTargetFolder: true
        ) != nil
    }

    func move(_ pin: ShortcutPin, toSpace spaceID: UUID) -> Bool {
        guard let pin = current(pin) else { return false }
        return placement.move(
            pin,
            to: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: nil,
            index: structure.topLevelSpacePinnedItems(for: spaceID).count,
            openTargetFolder: true
        ) != nil
    }

    private func current(_ pin: ShortcutPin) -> ShortcutPin? {
        guard let current = pins.shortcutPin(by: pin.id), current === pin else {
            return nil
        }
        return current
    }
}
