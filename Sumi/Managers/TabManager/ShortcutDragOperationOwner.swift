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
        if operation.fromContainer == operation.toContainer {
            return reorder(pin, in: operation.toContainer, to: operation.toIndex)
        }
        return move(pin, operation: operation)
    }

    private func move(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .spacePinned(let targetSpaceId)):
            return moveToTopLevelPinned(
                pin,
                in: targetSpaceId,
                at: operation.toIndex
            )

        case (.essentials, .folder(let targetFolderId)):
            return moveToFolder(pin, targetFolderId, at: operation.toIndex)

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
            return moveToTopLevelPinned(
                pin,
                in: targetSpaceId,
                at: operation.toIndex
            )

        case (.spacePinned, .folder(let targetFolderId)),
             (.folder, .folder(let targetFolderId)):
            return moveToFolder(pin, targetFolderId, at: operation.toIndex)

        case (.folder, .spacePinned(let targetSpaceId)):
            return moveToTopLevelPinned(
                pin,
                in: targetSpaceId,
                at: operation.toIndex
            )

        case (.spacePinned, .spaceRegular(let targetSpaceId)):
            return pinToRegular.convert(
                pin,
                into: targetSpaceId,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            )

        case (.folder, .spaceRegular(let targetSpaceId)):
            return pinToRegular.convert(
                pin,
                into: targetSpaceId,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            )

        case (.essentials, .essentials),
             (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return false
        }
    }

    private func reorder(
        _ pin: ShortcutPin,
        in container: TabDragManager.DragContainer,
        to visualBoundary: Int
    ) -> Bool {
        switch container {
        case .essentials:
            return placement.reorderEssential(pin, to: visualBoundary)
        case .spacePinned(let spaceID):
            return placement.reorderSpacePinned(
                pin,
                in: spaceID,
                to: visualBoundary
            )
        case .folder(let folderID):
            guard let spaceID = folders.spaceId(for: folderID) else {
                return false
            }
            return placement.reorderSpacePinned(
                pin,
                in: spaceID,
                to: visualBoundary
            )
        case .spaceRegular, .none:
            return false
        }
    }

    private func moveToTopLevelPinned(
        _ pin: ShortcutPin,
        in spaceID: UUID,
        at visualIndex: Int
    ) -> Bool {
        return placement.move(
            pin,
            to: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: nil,
            index: visualIndex,
            openTargetFolder: true
        ) != nil
    }

    private func moveToFolder(
        _ pin: ShortcutPin,
        _ folderID: UUID,
        at visualIndex: Int
    ) -> Bool {
        guard let spaceID = folders.spaceId(for: folderID) else { return false }
        return placement.move(
            pin,
            to: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: folderID,
            index: visualIndex,
            openTargetFolder: false
        ) != nil
    }
}
