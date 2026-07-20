import AppKit
import Foundation

@MainActor
final class TabFolderPlacementCommitTransaction {
    private let hierarchy: TabFolderHierarchyMutationService
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let folderOpenState: TabFolderOpenStateService
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        hierarchy: TabFolderHierarchyMutationService,
        spacePinnedStructure: SpacePinnedStructureOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        folderOpenState: TabFolderOpenStateService,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.hierarchy = hierarchy
        self.spacePinnedStructure = spacePinnedStructure
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.folderOpenState = folderOpenState
        self.structuralMutations = structuralMutations
    }

    func commit(
        _ folder: TabFolder,
        intent: TabFolderPlacementIntent
    ) -> Bool {
        switch intent {
        case .reorderTopLevel(let spaceID, let targetIndex):
            return spacePinnedVisualOrder.reorder(
                .folder(folder.id),
                in: spaceID,
                to: targetIndex
            )

        case .move(let parentFolderID, let spaceID, let targetIndex):
            return moveFolder(
                folder,
                toParentFolderID: parentFolderID,
                in: spaceID,
                targetIndex: targetIndex
            )
        }
    }

    private func moveFolder(
        _ folder: TabFolder,
        toParentFolderID parentFolderID: UUID?,
        in spaceID: UUID,
        targetIndex: Int
    ) -> Bool {
        let sourceParentID = folder.parentFolderId
        var sourceItems = hierarchy.childItems(
            in: sourceParentID,
            spaceID: spaceID
        )
        let sourceIndex = sourceItems.firstIndex(of: .folder(folder.id))
        if let sourceIndex { sourceItems.remove(at: sourceIndex) }

        let targetItems: [TabFolderContainerItem]
        let adjustedIndex: Int
        if sourceParentID == parentFolderID {
            targetItems = sourceItems
            adjustedIndex = sourceIndex.map {
                spacePinnedStructure.adjustedSameContainerInsertionIndex(
                    currentIndex: $0,
                    proposedIndex: targetIndex
                )
            } ?? targetIndex
        } else {
            hierarchy.applyChildItems(
                sourceItems,
                in: sourceParentID,
                spaceID: spaceID
            )
            targetItems = hierarchy.childItems(
                in: parentFolderID,
                spaceID: spaceID
            )
            adjustedIndex = targetIndex
        }

        var reorderedItems = targetItems
        let safeIndex = max(0, min(adjustedIndex, reorderedItems.count))
        reorderedItems.insert(.folder(folder.id), at: safeIndex)
        hierarchy.applyChildItems(
            reorderedItems,
            in: parentFolderID,
            spaceID: spaceID
        )
        if let parentFolderID {
            folderOpenState.openFolderIfNeeded(parentFolderID)
        }
        structuralMutations.schedulePersistence()
        return true
    }
}
