import Foundation
import SumiDomain

@MainActor
final class SidebarRegularTabShortcutTransaction {
    private let placement: ShortcutPinPlacementCommandService
    private let conversion: RegularTabShortcutConversionCommand
    private let favoritePlacement: FavoriteShortcutPlacementOwner
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        placement: ShortcutPinPlacementCommandService,
        conversion: RegularTabShortcutConversionCommand,
        favoritePlacement: FavoriteShortcutPlacementOwner,
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.placement = placement
        self.conversion = conversion
        self.favoritePlacement = favoritePlacement
        self.folders = folders
        self.pins = pins
    }

    func convert(
        _ tab: Tab,
        to role: ShortcutPinRole,
        profileID: UUID?,
        spaceID: UUID?,
        folderID: UUID?,
        at index: Int,
        openTargetFolder: Bool = true,
        preferredWindowID: UUID? = nil
    ) -> ShortcutPin? {
        conversion.convert(
            tab,
            destination: TabShortcutPinDestination(
                role: role,
                profileId: profileID,
                spaceId: spaceID,
                folderId: folderID,
                index: index,
                opensFolder: openTargetFolder
            ),
            preferredWindowId: preferredWindowID
        )
    }

    func resolvedFavoriteProfileID(
        for operation: DragOperation
    ) -> UUID? {
        favoritePlacement.resolvedProfileId(for: operation)
    }

    func folderSpaceID(for folderID: UUID) -> UUID? {
        folders.spaceId(for: folderID)
    }

    func reorderSpacePinned(
        _ tab: Tab,
        in spaceID: UUID,
        to index: Int
    ) -> Bool {
        if let shortcutID = tab.shortcutPinId,
           let pin = pins.shortcutPin(by: shortcutID) {
            return placement.reorderSpacePinned(pin, in: spaceID, to: index)
        }

        return convert(
            tab,
            to: .spacePinned,
            profileID: nil,
            spaceID: spaceID,
            folderID: nil,
            at: index
        ) != nil
    }

    func reorderFavorite(_ tab: Tab, to index: Int) -> Bool {
        guard let shortcutID = tab.shortcutPinId,
              let pin = pins.shortcutPin(by: shortcutID),
              pin.profileId != nil else {
            return false
        }
        return placement.reorderFavorite(pin, to: index)
    }
}
