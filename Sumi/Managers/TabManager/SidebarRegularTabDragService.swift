import Foundation
import SumiDomain

@MainActor
final class SidebarRegularTabDragService {
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
        regularOperation: SidebarRegularTabDragOperationKind,
        dragOperation operation: DragOperation
    ) -> Bool {
        let didMutate: Bool
        switch regularOperation {
        case .reorder where operation.toContainer == .essentials:
            didMutate = shortcuts.reorderEssential(tab, to: operation.toIndex)

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

        case .moveToEssentials
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId)
                || operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard let profileID = shortcuts.resolvedEssentialsProfileID(for: operation) else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .essential,
                profileID: profileID,
                spaceID: nil,
                folderID: nil,
                at: operation.toIndex,
                preferredWindowID: operation.scope.windowId
            ) != nil

        case .moveToRegular(let spaceID) where operation.fromContainer == .essentials:
            didMutate = regularTabs.place(tab, in: spaceID, at: operation.toIndex)

        case .moveToPinned(let spaceID) where operation.fromContainer == .essentials:
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

        case .moveToEssentials where isFolderContainer(operation.fromContainer):
            guard let profileID = shortcuts.resolvedEssentialsProfileID(for: operation) else {
                return false
            }
            didMutate = shortcuts.convert(
                tab,
                to: .essential,
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
             .moveToEssentials,
             .moveToRegular:
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
            return false
        }

        if didMutate {
            splitRetirement.dissolveActiveSplitIfNeeded(for: tab)
        }
        return didMutate
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
