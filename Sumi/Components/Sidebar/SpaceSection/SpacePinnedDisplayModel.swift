//
//  SpacePinnedDisplayModel.swift
//  Sumi
//

import Foundation

typealias SpacePinnedListItem = SplitGroupVisualListItem

enum SpacePinnedRenderedItem: Hashable {
    case item(SpacePinnedListItem)
    case dragPlaceholder
    case restoreGap(UUID)
}

struct SpacePinnedDisplayEntry: Identifiable {
    let item: SpacePinnedRenderedItem
    let dropIndex: Int
    let id: String
}

/// Derives the projected (drag-aware) list of space-pinned items and merges
/// in-flight shortcut "restore gap" placeholders, given a plain snapshot of
/// the relevant drag-projection state. Pure value type — no environment or
/// observed-object dependencies — so the projection/merge logic can be
/// exercised directly in tests.
struct SpacePinnedDisplayModel {
    struct DragProjectionSnapshot {
        let isDropProjectionActive: Bool
        let sourceContainer: TabDragManager.DragContainer?
        let dragItemId: UUID?
        let hoveredSpaceId: UUID?
        let hoveredSlot: Int?
        let folderDropIntent: FolderDropIntent
        /// Mirrors `SidebarDragState.shouldHideCommittedCrossContainerPlaceholder(into:targetAlreadyContainsDraggedItem:)`
        /// for the `.spacePinned(spaceId)` target, with `targetAlreadyContainsDraggedItem`
        /// already resolved by the caller.
        let shouldHideCommittedCrossContainerPlaceholder: (_ targetAlreadyContainsDraggedItem: Bool) -> Bool

        init(
            isDropProjectionActive: Bool,
            sourceContainer: TabDragManager.DragContainer?,
            dragItemId: UUID?,
            hoveredSpaceId: UUID?,
            hoveredSlot: Int?,
            folderDropIntent: FolderDropIntent,
            shouldHideCommittedCrossContainerPlaceholder: @escaping (_ targetAlreadyContainsDraggedItem: Bool) -> Bool
        ) {
            self.isDropProjectionActive = isDropProjectionActive
            self.sourceContainer = sourceContainer
            self.dragItemId = dragItemId
            self.hoveredSpaceId = hoveredSpaceId
            self.hoveredSlot = hoveredSlot
            self.folderDropIntent = folderDropIntent
            self.shouldHideCommittedCrossContainerPlaceholder = shouldHideCommittedCrossContainerPlaceholder
        }
    }

    let spaceId: UUID
    let items: [SpacePinnedListItem]
    let restoreGaps: [ShortcutRestoreGap]
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
        if let dragItemId = dragProjection.dragItemId {
            let targetAlreadyContainsDraggedItem = items.contains { $0.id == dragItemId }
            if dragProjection.shouldHideCommittedCrossContainerPlaceholder(targetAlreadyContainsDraggedItem) {
                return nil
            }
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

    /// Projected items with any in-flight shortcut restore gaps merged in,
    /// replacing the item they're restoring in place.
    var renderedItems: [SpacePinnedRenderedItem] {
        var rendered = projectedItems.map { item -> SpacePinnedRenderedItem in
            switch item {
            case .item(let listItem):
                return .item(listItem)
            case .placeholder:
                return .dragPlaceholder
            }
        }

        let gaps = restoreGaps.filter { $0.container == .spacePinned(spaceId) }
        for gap in gaps.sorted(by: { $0.index < $1.index }) {
            rendered.removeAll { item in
                if case .item(.shortcut(let pinId)) = item {
                    return pinId == gap.pinId
                }
                return false
            }
            rendered.insert(.restoreGap(gap.id), at: max(0, min(gap.index, rendered.count)))
        }

        return rendered
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
            case .dragPlaceholder, .restoreGap:
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
        case .restoreGap(let gapId):
            if let gap = restoreGaps.first(where: { $0.id == gapId }) {
                return "item-\(gap.pinId.uuidString)"
            }
            return "restore-gap-\(gapId.uuidString)"
        }
    }
}
