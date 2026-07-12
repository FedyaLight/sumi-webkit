import Foundation

enum SidebarDropProjection {
    static func modelInsertionIndex(
        fromProjectedIndex projectedIndex: Int,
        sourceIndex: Int?
    ) -> Int {
        let safeProjectedIndex = max(0, projectedIndex)
        guard let sourceIndex, sourceIndex < safeProjectedIndex else {
            return safeProjectedIndex
        }
        return safeProjectedIndex + 1
    }

    /// Maps a visual drop slot to the model insertion index, applying
    /// same-container source removal adjustment and projected-index clamping.
    static func operationIndex(
        visualIndex: Int,
        sourceContainer: TabDragManager.DragContainer,
        targetContainer: TabDragManager.DragContainer,
        sourceIndex: Int?,
        sourceItemCount: Int?
    ) -> Int {
        guard sourceContainer == targetContainer else {
            return visualIndex
        }

        let projectedVisualIndex = clampedProjectedVisualIndex(
            visualIndex,
            sourceIndex: sourceIndex,
            sourceItemCount: sourceItemCount
        )
        return modelInsertionIndex(
            fromProjectedIndex: projectedVisualIndex,
            sourceIndex: sourceIndex
        )
    }

    static func clampedProjectedVisualIndex(
        _ visualIndex: Int,
        sourceIndex: Int?,
        sourceItemCount: Int?
    ) -> Int {
        guard sourceIndex != nil, let sourceItemCount else {
            return visualIndex
        }
        return max(0, min(visualIndex, max(sourceItemCount - 1, 0)))
    }

    static func projectedItems<ID: Hashable>(
        itemIDs: [ID],
        sourceID: ID?,
        projectedInsertionIndex: Int?
    ) -> [ProjectedItem<ID>] {
        let sourceRemovedItems = itemIDs.filter { $0 != sourceID }
        guard let projectedInsertionIndex else {
            return sourceRemovedItems.map(ProjectedItem.item)
        }

        var items = sourceRemovedItems.map(ProjectedItem.item)
        let safeIndex = max(0, min(projectedInsertionIndex, items.count))
        items.insert(.placeholder, at: safeIndex)
        return items
    }

    static func projectedItems<ID: Hashable>(
        itemIDs: [ID],
        removesSourceID sourceID: ID?,
        insertsPlaceholderAt projectedInsertionIndex: Int?
    ) -> [ProjectedItem<ID>] {
        projectedItems(
            itemIDs: itemIDs,
            sourceID: sourceID,
            projectedInsertionIndex: projectedInsertionIndex
        )
    }
}

enum ProjectedItem<ID: Hashable>: Hashable {
    case item(ID)
    case placeholder
}
