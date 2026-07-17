import Foundation
import SumiDomain

@MainActor
final class ShortcutDragOperationOwner {
    private let placement: ShortcutPinPlacementCommandService
    private let pinToRegular: ShortcutPinToRegularTabService
    private let folders: TabFolderCollectionStateOwner
    private let essentialsPlacement: EssentialsShortcutPlacementOwner

    init(
        placement: ShortcutPinPlacementCommandService,
        pinToRegular: ShortcutPinToRegularTabService,
        folders: TabFolderCollectionStateOwner,
        essentialsPlacement: EssentialsShortcutPlacementOwner
    ) {
        self.placement = placement
        self.pinToRegular = pinToRegular
        self.folders = folders
        self.essentialsPlacement = essentialsPlacement
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            return placement.reorderEssential(pin, to: operation.toIndex)

        case (.essentials, .spacePinned(let targetSpaceId)):
            return placement.move(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: operation.toIndex,
                openTargetFolder: true
            ) != nil

        case (.essentials, .folder(let targetFolderId)):
            guard let targetSpaceId = folders.spaceId(for: targetFolderId) else {
                return false
            }
            return placement.move(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: targetFolderId,
                index: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case (.essentials, .spaceRegular(let targetSpaceId)):
            return pinToRegular.convert(
                pin,
                into: targetSpaceId,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            )

        case (.spacePinned, .essentials),
             (.folder, .essentials):
            guard let currentProfileId = essentialsPlacement.resolvedProfileId(
                for: operation
            ) else { return false }
            return placement.move(
                pin,
                to: .essential,
                profileId: currentProfileId,
                spaceId: nil,
                folderId: nil,
                index: operation.toIndex,
                openTargetFolder: true
            ) != nil

        case (.spacePinned, .spacePinned(let targetSpaceId)):
            return placement.move(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: operation.toIndex,
                openTargetFolder: true
            ) != nil

        case (.spacePinned, .folder(let targetFolderId)),
             (.folder, .folder(let targetFolderId)):
            guard let targetSpaceId = folders.spaceId(for: targetFolderId) else {
                return false
            }
            return placement.move(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: targetFolderId,
                index: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case (.folder, .spacePinned(let targetSpaceId)):
            return placement.move(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: operation.toIndex,
                openTargetFolder: true
            ) != nil

        case (.spacePinned, .spaceRegular(let targetSpaceId)),
             (.folder, .spaceRegular(let targetSpaceId)):
            return pinToRegular.convert(
                pin,
                into: targetSpaceId,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            )

        case (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return false
        }
    }
}
