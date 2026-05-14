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

    static func projectedInsertionIndex(
        fromModelIndex modelIndex: Int,
        sourceIndex: Int?
    ) -> Int {
        let safeModelIndex = max(0, modelIndex)
        guard let sourceIndex, sourceIndex < safeModelIndex else {
            return safeModelIndex
        }
        return safeModelIndex - 1
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
