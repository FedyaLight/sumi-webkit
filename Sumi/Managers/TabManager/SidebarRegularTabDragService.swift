import Foundation
import SumiDomain

@MainActor
final class SidebarRegularTabDragService {
    private enum Operation {
        case reorder(spaceID: UUID)
        case moveToPinned(spaceID: UUID)
        case moveToFolder(folderID: UUID)
        case moveToFavorite
        case moveToRegular(spaceID: UUID)
        case unsupported
    }

    private let shortcuts: SidebarRegularTabShortcutTransaction
    private let regularTabs: SidebarRegularTabPlacementTransaction
    private let splitRetirement: SidebarDraggedTabSplitRetirementTransaction

    init(
        shortcuts: SidebarRegularTabShortcutTransaction,
        regularTabs: SidebarRegularTabPlacementTransaction,
        splitRetirement: SidebarDraggedTabSplitRetirementTransaction
    ) {
        self.shortcuts = shortcuts
        self.regularTabs = regularTabs
        self.splitRetirement = splitRetirement
    }

    @discardableResult
    func execute(
        _ tab: Tab,
        dragOperation operation: DragOperation
    ) -> Bool {
        let regularOperation = classify(operation)
        let didMutate: Bool
        switch regularOperation {
        case .reorder where operation.toContainer == .favorite:
            didMutate = shortcuts.reorderFavorite(tab, to: operation.toIndex)

        case .reorder(let spaceID) where operation.toContainer == .spacePinned(spaceID):
            didMutate = shortcuts.reorderSpacePinned(tab, in: spaceID, to: operation.toIndex)

        case .reorder(let spaceID) where operation.toContainer == .spaceRegular(spaceID):
            didMutate = regularTabs.reorder(tab, in: spaceID, to: operation.toIndex)

        case .moveToPinned(let targetSpaceID)
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId):
            didMutate = shortcuts.convert(
                tab,
                to: .spacePinned,
                profileID: nil,
                spaceID: targetSpaceID,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToRegular(let targetSpaceID)
            where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            didMutate = regularTabs.place(tab, in: targetSpaceID, at: operation.toIndex)

        case .moveToFavorite
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId)
                || operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard let profileID = shortcuts.resolvedFavoriteProfileID(for: operation) else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .favorite,
                profileID: profileID,
                spaceID: nil,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToRegular(let spaceID) where operation.fromContainer == .favorite:
            didMutate = regularTabs.place(tab, in: spaceID, at: operation.toIndex)

        case .moveToPinned(let spaceID) where operation.fromContainer == .favorite:
            didMutate = shortcuts.convert(
                tab,
                to: .spacePinned,
                profileID: nil,
                spaceID: spaceID,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToFolder(let targetFolderID) where isFolderContainer(operation.fromContainer):
            guard case .folder(let sourceFolderID) = operation.fromContainer,
                  let spaceID = tab.spaceId else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .spacePinned,
                profileID: nil,
                spaceID: spaceID,
                folderID: sourceFolderID == targetFolderID ? sourceFolderID : targetFolderID,
                at: operation.toIndex,
                openTargetFolder: false,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToFavorite where isFolderContainer(operation.fromContainer):
            guard let profileID = shortcuts.resolvedFavoriteProfileID(for: operation) else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .favorite,
                profileID: profileID,
                spaceID: nil,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToPinned(let spaceID) where isFolderContainer(operation.fromContainer):
            didMutate = shortcuts.convert(
                tab,
                to: .spacePinned,
                profileID: nil,
                spaceID: spaceID,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToRegular(let spaceID) where isFolderContainer(operation.fromContainer):
            didMutate = regularTabs.place(tab, in: spaceID, at: operation.toIndex)

        case .moveToFolder(let targetFolderID)
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId),
             .moveToFolder(let targetFolderID)
            where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard let targetSpaceID = shortcuts.folderSpaceID(for: targetFolderID),
                  targetSpaceID == operation.scope.spaceId else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .spacePinned,
                profileID: nil,
                spaceID: targetSpaceID,
                folderID: targetFolderID,
                at: operation.toIndex,
                openTargetFolder: false,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .unsupported,
             .reorder,
             .moveToPinned,
             .moveToFolder,
             .moveToFavorite,
             .moveToRegular:
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
            return false
        }

        if didMutate {
            splitRetirement.dissolveActiveSplitIfNeeded(for: tab)
        }
        return didMutate
    }

    private func classify(_ operation: DragOperation) -> Operation {
        switch (operation.fromContainer, operation.toContainer) {
        case (.favorite, .favorite):
            return .reorder(spaceID: operation.scope.spaceId)

        case (.spacePinned(let fromSpaceID), .spacePinned(let toSpaceID))
            where fromSpaceID == toSpaceID:
            return .reorder(spaceID: toSpaceID)

        case (.spaceRegular(let fromSpaceID), .spaceRegular(let toSpaceID))
            where fromSpaceID == toSpaceID:
            return .reorder(spaceID: toSpaceID)

        case (.spaceRegular, .spacePinned(let targetSpaceID)),
             (.favorite, .spacePinned(let targetSpaceID)),
             (.folder, .spacePinned(let targetSpaceID)):
            return .moveToPinned(spaceID: targetSpaceID)

        case (.spaceRegular, .folder(let folderID)),
             (.spacePinned, .folder(let folderID)),
             (.folder, .folder(let folderID)):
            return .moveToFolder(folderID: folderID)

        case (.spaceRegular, .favorite),
             (.spacePinned, .favorite),
             (.folder, .favorite):
            return .moveToFavorite

        case (.spacePinned, .spaceRegular(let targetSpaceID)),
             (.favorite, .spaceRegular(let targetSpaceID)),
             (.folder, .spaceRegular(let targetSpaceID)):
            return .moveToRegular(spaceID: targetSpaceID)

        case (.favorite, .folder),
             (.spacePinned, .spacePinned),
             (.spaceRegular, .spaceRegular),
             (.none, _),
             (_, .none):
            return .unsupported
        }
    }

    private func isFolderContainer(
        _ container: TabDragManager.DragContainer
    ) -> Bool {
        if case .folder = container {
            return true
        }
        return false
    }
}
