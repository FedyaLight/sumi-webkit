import Foundation

@MainActor
final class ShortcutDragOperationOwner {
    struct Dependencies {
        let reorderEssential: @MainActor (ShortcutPin, Int) -> Bool
        let moveShortcutPin: @MainActor (ShortcutPin, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?
        let folderSpaceId: @MainActor (UUID) -> UUID?
        let resolvedEssentialsProfileId: @MainActor (DragOperation) -> UUID?
        let convertShortcutPinToRegularTab: @MainActor (ShortcutPin, UUID, Int?) -> Bool
        let removeShortcutPinFromContainers: @MainActor (ShortcutPin) -> Void
        let insertRegularTabFromShortcut: @MainActor (ShortcutPin, UUID, Int?) -> Tab
        let scheduleStructuralPersistence: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            return dependencies.reorderEssential(pin, operation.toIndex)

        case (.essentials, .spacePinned(let targetSpaceId)):
            return dependencies.moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.essentials, .folder(let targetFolderId)):
            guard let targetSpaceId = dependencies.folderSpaceId(targetFolderId) else { return false }
            return dependencies.moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                targetFolderId,
                operation.toIndex,
                false
            ) != nil

        case (.essentials, .spaceRegular(let targetSpaceId)):
            return dependencies.convertShortcutPinToRegularTab(pin, targetSpaceId, operation.toIndex)

        case (.spacePinned, .essentials),
             (.folder, .essentials):
            guard let currentProfileId = dependencies.resolvedEssentialsProfileId(operation) else { return false }
            return dependencies.moveShortcutPin(
                pin,
                .essential,
                currentProfileId,
                nil,
                nil,
                operation.toIndex,
                true
            ) != nil

        case (.spacePinned, .spacePinned(let targetSpaceId)):
            return dependencies.moveShortcutPin(
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
            guard let targetSpaceId = dependencies.folderSpaceId(targetFolderId) else { return false }
            return dependencies.moveShortcutPin(
                pin,
                .spacePinned,
                nil,
                targetSpaceId,
                targetFolderId,
                operation.toIndex,
                false
            ) != nil

        case (.folder, .spacePinned(let targetSpaceId)):
            return dependencies.moveShortcutPin(
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
            dependencies.removeShortcutPinFromContainers(pin)
            _ = dependencies.insertRegularTabFromShortcut(pin, targetSpaceId, operation.toIndex)
            dependencies.scheduleStructuralPersistence()
            return true

        case (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return false
        }
    }
}
