//
//  SpacePinnedListProjection.swift
//  Sumi
//

import Foundation

typealias SpacePinnedListItem = SplitGroupVisualListItem

enum SpacePinnedRenderedItem: Hashable {
    case item(SpacePinnedListItem)
    case dragPlaceholder
}

struct SpacePinnedDisplayEntry: Identifiable {
    let item: SpacePinnedRenderedItem
    let dropIndex: Int
    let id: String
}

/// Derives the projected (drag-aware) list of space-pinned items from a snapshot of
/// the relevant drag-projection state. Pure value type — no environment or
/// observed-object dependencies — so the projection/merge logic can be
/// exercised directly in tests.
struct SpacePinnedListProjection {
    struct DragProjectionSnapshot {
        let isDropProjectionActive: Bool
        let sourceContainer: TabDragManager.DragContainer?
        let dragItemId: UUID?
        let hoveredSpaceId: UUID?
        let hoveredSlot: Int?
        let folderDropIntent: FolderDropIntent
        /// Resolved at the observation boundary so the projection remains a
        /// closure-free value that can be compared and tested deterministically.
        let hidesCommittedCrossContainerPlaceholder: Bool

        init(
            isDropProjectionActive: Bool,
            sourceContainer: TabDragManager.DragContainer?,
            dragItemId: UUID?,
            hoveredSpaceId: UUID?,
            hoveredSlot: Int?,
            folderDropIntent: FolderDropIntent,
            hidesCommittedCrossContainerPlaceholder: Bool
        ) {
            self.isDropProjectionActive = isDropProjectionActive
            self.sourceContainer = sourceContainer
            self.dragItemId = dragItemId
            self.hoveredSpaceId = hoveredSpaceId
            self.hoveredSlot = hoveredSlot
            self.folderDropIntent = folderDropIntent
            self.hidesCommittedCrossContainerPlaceholder = hidesCommittedCrossContainerPlaceholder
        }
    }

    let spaceId: UUID
    let items: [SpacePinnedListItem]
    let dragProjection: DragProjectionSnapshot

    var projectedSourceItem: SpacePinnedListItem? {
        guard dragProjection.isDropProjectionActive,
              dragProjection.sourceContainer == .spacePinned(spaceId),
              let dragItemId = dragProjection.dragItemId else {
            return nil
        }
        return items.first { $0.id == dragItemId }
    }

    var projectedInsertionIndex: Int? {
        guard dragProjection.isDropProjectionActive,
              dragProjection.hoveredSpaceId == spaceId,
              let slot = dragProjection.hoveredSlot else {
            return nil
        }
        guard dragProjection.folderDropIntent == .none else {
            return nil
        }
        if dragProjection.dragItemId != nil,
           dragProjection.hidesCommittedCrossContainerPlaceholder {
            return nil
        }
        return slot
    }

    var projectedItems: [ProjectedItem<SpacePinnedListItem>] {
        SidebarDropProjection.projectedItems(
            itemIDs: items,
            removesSourceID: projectedSourceItem,
            insertsPlaceholderAt: projectedInsertionIndex
        )
    }

    var renderedItems: [SpacePinnedRenderedItem] {
        projectedItems.map { item -> SpacePinnedRenderedItem in
            switch item {
            case .item(let listItem):
                return .item(listItem)
            case .placeholder:
                return .dragPlaceholder
            }
        }
    }

    /// Rendered items paired with a stable drop index (counting only real
    /// items, not placeholders/gaps) and a stable identity for `ForEach`.
    var displayEntries: [SpacePinnedDisplayEntry] {
        var itemCount = 0
        return renderedItems.map { item in
            let entry = SpacePinnedDisplayEntry(
                item: item,
                dropIndex: itemCount,
                id: displayID(for: item, placeholderIndex: itemCount)
            )
            switch item {
            case .item:
                itemCount += 1
            case .dragPlaceholder:
                break
            }
            return entry
        }
    }

    func displayID(for item: SpacePinnedRenderedItem, placeholderIndex: Int) -> String {
        switch item {
        case .item(let listItem):
            return "item-\(listItem.id.uuidString)"
        case .dragPlaceholder:
            if let dragItemId = dragProjection.dragItemId {
                return "item-\(dragItemId.uuidString)"
            }
            return "placeholder-\(placeholderIndex)"
        }
    }
}
