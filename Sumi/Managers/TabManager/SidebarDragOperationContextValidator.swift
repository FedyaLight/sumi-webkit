import Foundation

@MainActor
enum SidebarDragOperationContextValidator {
    typealias FolderSpaceResolver = (UUID) -> UUID?
    typealias ShortcutPinResolver = (UUID) -> ShortcutPin?

    static func validate(
        operation: DragOperation,
        spaceProfileId: UUID?,
        folderSpaceId: FolderSpaceResolver,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
        operation.fromContainer == operation.scope.sourceContainer
            && scopeProfileMatchesSpace(operation.scope, spaceProfileId: spaceProfileId)
            && operationPayloadMatchesScope(operation, shortcutPin: shortcutPin)
            && sidebarContainer(operation.fromContainer, isIn: operation.scope, folderSpaceId: folderSpaceId)
            && sidebarContainer(operation.toContainer, isIn: operation.scope, folderSpaceId: folderSpaceId)
            && payloadOwnershipMatchesSource(
                operation,
                folderSpaceId: folderSpaceId,
                shortcutPin: shortcutPin
            )
    }

    private static func scopeProfileMatchesSpace(
        _ scope: SidebarDragScope,
        spaceProfileId: UUID?
    ) -> Bool {
        guard let spaceProfileId,
              let scopeProfileId = scope.profileId else {
            return true
        }
        return spaceProfileId == scopeProfileId
    }

    private static func operationPayloadMatchesScope(
        _ operation: DragOperation,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
        switch (operation.scope.sourceItemKind, operation.payload) {
        case (.folder, .folder(let folder)):
            return folder.id == operation.scope.sourceItemId
        case (.folder, _):
            return false
        case (.splitGroup, .splitGroup(let group)):
            return group.id == operation.scope.sourceItemId
        case (.splitGroup, _):
            return false
        case (.tab, .pin(let pin)):
            return pin.id == operation.scope.sourceItemId
        case (.tab, .tab(let tab)):
            return tab.id == operation.scope.sourceItemId
                || tab.shortcutPinId == operation.scope.sourceItemId
                || shortcutPin(operation.scope.sourceItemId)?.id == tab.shortcutPinId
        case (.tab, .folder),
             (.tab, .splitGroup):
            return false
        }
    }

    private static func sidebarContainer(
        _ container: TabDragManager.DragContainer,
        isIn scope: SidebarDragScope,
        folderSpaceId: FolderSpaceResolver
    ) -> Bool {
        switch container {
        case .none:
            return false
        case .favorite:
            return scope.profileId != nil
        case .spacePinned(let spaceId),
             .spaceRegular(let spaceId):
            return spaceId == scope.spaceId
        case .folder(let folderId):
            return folderSpaceId(folderId) == scope.spaceId
        }
    }

    private static func payloadOwnershipMatchesSource(
        _ operation: DragOperation,
        folderSpaceId: FolderSpaceResolver,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
        switch operation.payload {
        case .splitGroup(let group):
            switch (group.container, operation.fromContainer) {
            case (.regularTabs(let spaceID), .spaceRegular(let sourceSpaceID)):
                return spaceID == operation.scope.spaceId
                    && spaceID == sourceSpaceID

            case (.favoriteSidebar(let profileID, _), .favorite):
                return profileID == nil
                    || profileID == operation.scope.profileId

            case (
                .shortcutSidebar(let spaceID, _, nil, _),
                .spacePinned(let sourceSpaceID)
            ):
                return spaceID == operation.scope.spaceId
                    && spaceID == sourceSpaceID

            case (
                .shortcutSidebar(let spaceID, _, let folderID?, _),
                .folder(let sourceFolderID)
            ):
                return spaceID == operation.scope.spaceId
                    && folderID == sourceFolderID
                    && folderSpaceId(folderID) == spaceID

            default:
                return false
            }

        case .folder(let folder):
            switch operation.fromContainer {
            case .spacePinned(let spaceId):
                return folder.spaceId == operation.scope.spaceId
                    && folder.spaceId == spaceId
                    && folder.parentFolderId == nil

            case .folder(let parentFolderId):
                return folder.spaceId == operation.scope.spaceId
                    && folder.parentFolderId == parentFolderId
                    && folderSpaceId(parentFolderId) == operation.scope.spaceId

            default:
                return false
            }

        case .pin(let pin):
            return shortcutPinMatchesSource(pin, operation: operation, folderSpaceId: folderSpaceId)

        case .tab(let tab):
            if let shortcutId = tab.shortcutPinId,
               let pin = shortcutPin(shortcutId) {
                return shortcutPinMatchesSource(pin, operation: operation, folderSpaceId: folderSpaceId)
            }

            guard case .spaceRegular(let spaceId) = operation.fromContainer else {
                return false
            }
            return tab.spaceId == operation.scope.spaceId
                && tab.spaceId == spaceId
        }
    }

    private static func shortcutPinMatchesSource(
        _ pin: ShortcutPin,
        operation: DragOperation,
        folderSpaceId: FolderSpaceResolver
    ) -> Bool {
        switch (pin.role, operation.fromContainer) {
        case (.favorite, .favorite):
            return pin.profileId == operation.scope.profileId
        case (.spacePinned, .spacePinned(let spaceId)):
            return pin.spaceId == operation.scope.spaceId
                && pin.spaceId == spaceId
                && pin.folderId == nil
        case (.spacePinned, .folder(let folderId)):
            return pin.spaceId == operation.scope.spaceId
                && pin.folderId == folderId
                && folderSpaceId(folderId) == operation.scope.spaceId
        default:
            return false
        }
    }
}
