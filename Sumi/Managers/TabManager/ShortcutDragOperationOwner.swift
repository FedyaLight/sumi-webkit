import Foundation
import SumiDomain

@MainActor
final class ShortcutDragOperationOwner {
    private let reorderEssential: @MainActor (ShortcutPin, Int) -> Bool
    private let moveShortcutPin: @MainActor (ShortcutPin, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?
    private let folderSpaceId: @MainActor (UUID) -> UUID?
    private let resolvedEssentialsProfileId: @MainActor (DragOperation) -> UUID?
    private let convertShortcutPinToRegularTab: @MainActor (ShortcutPin, UUID, Int?, UUID?) -> Bool

    init(
        reorderEssential: @escaping @MainActor (ShortcutPin, Int) -> Bool,
        moveShortcutPin: @escaping @MainActor (ShortcutPin, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?,
        folderSpaceId: @escaping @MainActor (UUID) -> UUID?,
        resolvedEssentialsProfileId: @escaping @MainActor (DragOperation) -> UUID?,
        convertShortcutPinToRegularTab: @escaping @MainActor (ShortcutPin, UUID, Int?, UUID?) -> Bool
    ) {
        self.reorderEssential = reorderEssential
        self.moveShortcutPin = moveShortcutPin
        self.folderSpaceId = folderSpaceId
        self.resolvedEssentialsProfileId = resolvedEssentialsProfileId
        self.convertShortcutPinToRegularTab = convertShortcutPinToRegularTab
    }

    convenience init(tabManager: TabManager) {
        self.init(
            reorderEssential: { [weak tabManager] pin, index in
                tabManager?.shortcutPinCommandOwner.reorderEssential(pin, to: index) ?? false
            },
            moveShortcutPin: { [weak tabManager] pin, role, profileId, spaceId, folderId, index, openTargetFolder in
                tabManager?.shortcutPinCommandOwner.moveShortcutPin(
                    pin,
                    to: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    index: index,
                    openTargetFolder: openTargetFolder
                )
            },
            folderSpaceId: { [weak tabManager] folderId in
                tabManager?.folderCollectionStateOwner.spaceId(for: folderId)
            },
            resolvedEssentialsProfileId: { [weak tabManager] operation in
                tabManager?.essentialsShortcutPlacementOwner.resolvedProfileId(for: operation)
            },
            convertShortcutPinToRegularTab: { [weak tabManager] pin, spaceId, targetIndex, preferredWindowId in
                tabManager?.shortcutPinCommandOwner.convertShortcutPinToRegularTab(
                    pin,
                    in: spaceId,
                    at: targetIndex,
                    preferredWindowId: preferredWindowId
                ) ?? false
            }
        )
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            return reorderEssential(pin, operation.toIndex)

        case (.essentials, .spacePinned(let targetSpaceId)):
            return moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.essentials, .folder(let targetFolderId)):
            guard let targetSpaceId = folderSpaceId(targetFolderId) else { return false }
            return moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                targetFolderId,
                operation.toIndex,
                false
            ) != nil

        case (.essentials, .spaceRegular(let targetSpaceId)):
            return convertShortcutPinToRegularTab(
                pin,
                targetSpaceId,
                operation.toIndex,
                operation.scope.windowId
            )

        case (.spacePinned, .essentials),
             (.folder, .essentials):
            guard let currentProfileId = resolvedEssentialsProfileId(operation) else { return false }
            return moveShortcutPin(
                pin,
                .essential,
                currentProfileId,
                nil,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.spacePinned, .spacePinned(let targetSpaceId)):
            return moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.spacePinned, .folder(let targetFolderId)),
             (.folder, .folder(let targetFolderId)):
            guard let targetSpaceId = folderSpaceId(targetFolderId) else { return false }
            return moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                targetFolderId,
                operation.toIndex,
                false
            ) != nil

        case (.folder, .spacePinned(let targetSpaceId)):
            return moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.spacePinned, .spaceRegular(let targetSpaceId)),
             (.folder, .spaceRegular(let targetSpaceId)):
            return convertShortcutPinToRegularTab(
                pin,
                targetSpaceId,
                operation.toIndex,
                operation.scope.windowId
            )

        case (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return false
        }
    }
}
