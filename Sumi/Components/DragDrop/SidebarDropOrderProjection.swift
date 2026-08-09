import Foundation

/// Storage adapter for a visual sidebar row boundary. DnD callers only use
/// row slots; container-specific record layouts remain behind this seam.
@MainActor
protocol SidebarDropOrderProjecting {
    func storageIndex(
        forVisualIndex visualIndex: Int,
        in container: TabDragManager.DragContainer
    ) -> Int

    func mutationIndex(for intent: SidebarDragCommitIntent) -> Int?
}

extension SidebarDropOrderProjecting {
    func mutationIndex(for intent: SidebarDragCommitIntent) -> Int? {
        storageIndex(
            forVisualIndex: intent.presentedVisualIndex,
            in: intent.toContainer
        )
    }

    func storageSlot(for visualSlot: DropZoneSlot) -> DropZoneSlot {
        let index = storageIndex(
            forVisualIndex: visualSlot.visualIndex,
            in: visualSlot.asDragContainer
        )
        switch visualSlot {
        case .empty:
            return .empty
        case .favorite:
            return .favorite(slot: index)
        case .spacePinned(let spaceID, _):
            return .spacePinned(spaceId: spaceID, slot: index)
        case .spaceRegular(let spaceID, _):
            return .spaceRegular(spaceId: spaceID, slot: index)
        case .folder(let folderID, _):
            return .folder(folderId: folderID, slot: index)
        }
    }
}

@MainActor
struct SidebarIdentityDropOrderProjection: SidebarDropOrderProjecting {
    func storageIndex(
        forVisualIndex visualIndex: Int,
        in container: TabDragManager.DragContainer
    ) -> Int {
        max(0, visualIndex)
    }
}

@MainActor
final class SidebarDropOrderProjection: SidebarDropOrderProjecting {
    private let regularTabs: RegularTabCollectionOwner
    private let splitOrdering: SplitGroupSidebarOrderingService

    init(
        regularTabs: RegularTabCollectionOwner,
        splitOrdering: SplitGroupSidebarOrderingService
    ) {
        self.regularTabs = regularTabs
        self.splitOrdering = splitOrdering
    }

    func storageIndex(
        forVisualIndex visualIndex: Int,
        in container: TabDragManager.DragContainer
    ) -> Int {
        guard case .spaceRegular(let spaceID) = container else {
            return max(0, visualIndex)
        }
        return SidebarVisualSceneProjection.regularRun(
            tabIDs: regularTabs.tabs(in: spaceID).map(\.id),
            groups: splitOrdering.regularGroups(for: spaceID)
        ).rawInsertionIndex(atVisualBoundary: visualIndex)
    }

    func mutationIndex(for intent: SidebarDragCommitIntent) -> Int? {
        if case .spaceRegular(let spaceID) = intent.toContainer,
           let boundary = intent.presentedRegularBoundary {
            let run = SidebarVisualSceneProjection.regularRun(
                tabIDs: regularTabs.tabs(in: spaceID).map(\.id),
                groups: splitOrdering.regularGroups(for: spaceID)
            )
            guard let visualIndex = run.visualIndex(for: boundary) else {
                return nil
            }
            return run.rawInsertionIndex(atVisualBoundary: visualIndex)
        }

        guard intent.fromContainer == .favorite,
              intent.toContainer == .favorite else {
            return storageIndex(
                forVisualIndex: intent.presentedVisualIndex,
                in: intent.toContainer
            )
        }

        let sourceItems = splitOrdering.favoriteItems(
            for: intent.scope.profileId
        )
        let sourceIndex = sourceItems.firstIndex {
            intent.payload.matchesSidebarVisualItem(
                $0,
                sourceItemID: intent.scope.sourceItemId
            )
        }
        return SidebarDropProjection.operationIndex(
            visualIndex: intent.presentedVisualIndex,
            sourceContainer: intent.fromContainer,
            targetContainer: intent.toContainer,
            sourceIndex: sourceIndex,
            sourceItemCount: sourceItems.count
        )
    }
}

@MainActor
private extension DragOperation.Payload {
    func matchesSidebarVisualItem(
        _ item: SplitGroupVisualListItem,
        sourceItemID: UUID
    ) -> Bool {
        switch item {
        case .folder(let folderID):
            guard folderID != sourceItemID else { return true }
            guard case .folder(let folder) = self else { return false }
            return folder.id == folderID
        case .shortcut(let pinID):
            guard pinID != sourceItemID else { return true }
            switch self {
            case .pin(let pin):
                return pin.id == pinID
            case .tab(let tab):
                return tab.shortcutPinId == pinID
            case .folder, .splitGroup:
                return false
            }
        case .splitGroup(let groupID):
            guard groupID != sourceItemID else { return true }
            guard case .splitGroup(let group) = self else { return false }
            return group.id == groupID
        }
    }
}
