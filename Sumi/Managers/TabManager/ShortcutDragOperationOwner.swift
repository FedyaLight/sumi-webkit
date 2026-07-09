import Foundation
import SumiDomain

@MainActor
final class ShortcutDragOperationOwner {
    private let reorderEssential: @MainActor (ShortcutPin, Int) -> Bool
    private let moveShortcutPin: @MainActor (ShortcutPin, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?
    private let folderSpaceId: @MainActor (UUID) -> UUID?
    private let resolvedEssentialsProfileId: @MainActor (DragOperation) -> UUID?
    private let convertShortcutPinToRegularTab: @MainActor (ShortcutPin, UUID, Int?) -> Bool
    private let removeShortcutPinFromContainers: @MainActor (ShortcutPin) -> Void
    private let insertRegularTabFromShortcut: @MainActor (ShortcutPin, UUID, Int?) -> Tab
    private let scheduleStructuralPersistence: @MainActor () -> Void

    init(
        reorderEssential: @escaping @MainActor (ShortcutPin, Int) -> Bool,
        moveShortcutPin: @escaping @MainActor (ShortcutPin, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?,
        folderSpaceId: @escaping @MainActor (UUID) -> UUID?,
        resolvedEssentialsProfileId: @escaping @MainActor (DragOperation) -> UUID?,
        convertShortcutPinToRegularTab: @escaping @MainActor (ShortcutPin, UUID, Int?) -> Bool,
        removeShortcutPinFromContainers: @escaping @MainActor (ShortcutPin) -> Void,
        insertRegularTabFromShortcut: @escaping @MainActor (ShortcutPin, UUID, Int?) -> Tab,
        scheduleStructuralPersistence: @escaping @MainActor () -> Void
    ) {
        self.reorderEssential = reorderEssential
        self.moveShortcutPin = moveShortcutPin
        self.folderSpaceId = folderSpaceId
        self.resolvedEssentialsProfileId = resolvedEssentialsProfileId
        self.convertShortcutPinToRegularTab = convertShortcutPinToRegularTab
        self.removeShortcutPinFromContainers = removeShortcutPinFromContainers
        self.insertRegularTabFromShortcut = insertRegularTabFromShortcut
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
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
            convertShortcutPinToRegularTab: { [weak tabManager] pin, spaceId, targetIndex in
                tabManager?.shortcutPinCommandOwner.convertShortcutPinToRegularTab(pin, in: spaceId, at: targetIndex) ?? false
            },
            removeShortcutPinFromContainers: { [weak tabManager] pin in
                tabManager?.shortcutPinStoreOwner.removeFromContainers(pin)
            },
            insertRegularTabFromShortcut: { [weak tabManager] pin, spaceId, targetIndex in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.shortcutLiveTabOwner.insertRegularTabFromShortcut(pin, into: spaceId, at: targetIndex)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
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
            return convertShortcutPinToRegularTab(pin, targetSpaceId, operation.toIndex)

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
            removeShortcutPinFromContainers(pin)
            _ = insertRegularTabFromShortcut(pin, targetSpaceId, operation.toIndex)
            scheduleStructuralPersistence()
            return true

        case (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return false
        }
    }
}
