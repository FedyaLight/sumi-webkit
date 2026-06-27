//
//  SidebarEssentialsProjectionPolicy.swift
//  Sumi
//

import SwiftUI

struct SidebarEssentialsProjectedRow {
    let items: [ShortcutPin?]
    let startSlot: Int
    let visualColumnCount: Int
    let tileSize: CGSize
}

struct SidebarEssentialsProjectedLayout {
    let layoutItems: [ShortcutPin?]
    let visibleItems: [ShortcutPin?]
    let capacityColumnCount: Int
    let tileSize: CGSize
    let rows: [SidebarEssentialsProjectedRow]
    let visibleRows: [SidebarEssentialsProjectedRow]
    let canAcceptDrop: Bool

    var columnCount: Int {
        capacityColumnCount
    }

    var projectedItemCount: Int {
        layoutItems.count
    }

    var visibleItemCount: Int {
        visibleItems.count
    }

    var visibleRowCount: Int {
        visibleRows.count
    }

    var visualColumnSignature: [Int] {
        rows.map(\.visualColumnCount)
    }
}

@MainActor
enum SidebarEssentialsProjectionPolicy {
    static let maxColumns = TabManager.EssentialsCapacityPolicy.maxColumns
    static let maxRows = TabManager.EssentialsCapacityPolicy.maxRows
    static let maxItems = maxColumns * maxRows

    static func make(
        items: [ShortcutPin],
        width: CGFloat,
        configuration: PinnedTabsConfiguration,
        dragState: SidebarDragState
    ) -> SidebarEssentialsProjectedLayout {
        let baseVisibleItems = resolvedVisibleItems(
            from: items,
            dragState: dragState
        )
        let canAcceptDrop = baseVisibleItems.count < maxItems
        let layoutItems = resolvedLayoutItems(
            from: baseVisibleItems,
            dragState: dragState,
            canAcceptDrop: canAcceptDrop,
            essentialsStoreIsEmpty: items.isEmpty
        )
        let capacityColumnCount = resolvedCapacityColumnCount(
            for: width,
            configuration: configuration
        )
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: capacityColumnCount,
            configuration: configuration
        )
        let tileSize = CGSize(width: tileWidth, height: configuration.height)

        return SidebarEssentialsProjectedLayout(
            layoutItems: layoutItems,
            visibleItems: baseVisibleItems,
            capacityColumnCount: capacityColumnCount,
            tileSize: tileSize,
            rows: projectedRows(
                from: layoutItems,
                capacityColumnCount: capacityColumnCount,
                width: width,
                configuration: configuration
            ),
            visibleRows: projectedRows(
                from: baseVisibleItems,
                capacityColumnCount: capacityColumnCount,
                width: width,
                configuration: configuration
            ),
            canAcceptDrop: canAcceptDrop
        )
    }

    static func projectedCountAfterDrop(
        itemIDs: [UUID],
        visibleItemCount: Int,
        layoutItemCount: Int,
        canAcceptDrop: Bool,
        dragState: SidebarDragState
    ) -> Int {
        let safeVisibleItemCount = max(visibleItemCount, 0)
        guard canAcceptDrop else { return min(safeVisibleItemCount, maxItems) }

        let isDraggingExistingEssential = dragState.projectionDragItemId.map { itemIDs.contains($0) } ?? false
        let isHoveringEssentials = {
            guard dragState.isDropProjectionActive,
                  case .essentials = dragState.projectionHoveredSlot else {
                return false
            }
            return true
        }()

        let emptyStorePlaceholderActive = dragState.isDropProjectionActive
            && canAcceptDrop
            && itemIDs.isEmpty
            && safeVisibleItemCount == 0

        if isHoveringEssentials || emptyStorePlaceholderActive {
            let floorCount = emptyStorePlaceholderActive ? 1 : 0
            return min(max(max(layoutItemCount, safeVisibleItemCount), floorCount), maxItems)
        }

        if isDraggingExistingEssential {
            return min(safeVisibleItemCount, maxItems)
        }

        return min(safeVisibleItemCount + 1, maxItems)
    }

    static func neededRowCountAfterDrop(
        itemIDs: [UUID],
        visibleItemCount: Int,
        layoutItemCount: Int,
        columnCount: Int,
        canAcceptDrop: Bool,
        dragState: SidebarDragState
    ) -> Int {
        let projectedCount = projectedCountAfterDrop(
            itemIDs: itemIDs,
            visibleItemCount: visibleItemCount,
            layoutItemCount: layoutItemCount,
            canAcceptDrop: canAcceptDrop,
            dragState: dragState
        )
        let safeColumnCount = max(columnCount, 1)
        return min(
            maxRows,
            max(1, Int(ceil(Double(max(projectedCount, 1)) / Double(safeColumnCount))))
        )
    }

    private static func resolvedVisibleItems(
        from items: [ShortcutPin],
        dragState: SidebarDragState
    ) -> [ShortcutPin?] {
        guard let projectionDragItemId = dragState.projectionDragItemId else {
            return items.map { Optional($0) }
        }

        let isDraggingExistingEssential: Bool = {
            guard dragState.isDropProjectionActive,
                  dragState.projectionDragScope?.sourceContainer == .essentials else {
                return false
            }
            return items.contains { $0.id == projectionDragItemId }
        }()

        return items.compactMap { item -> ShortcutPin? in
            if item.id == projectionDragItemId, isDraggingExistingEssential {
                return nil
            }
            return item
        }
    }

    private static func resolvedLayoutItems(
        from items: [ShortcutPin?],
        dragState: SidebarDragState,
        canAcceptDrop: Bool,
        essentialsStoreIsEmpty: Bool
    ) -> [ShortcutPin?] {
        var layoutItems = items

        guard dragState.isDropProjectionActive, canAcceptDrop else {
            return layoutItems
        }

        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .essentials,
                targetAlreadyContainsDraggedItem: items.contains { $0?.id == projectionDragItemId }
           ) {
            return layoutItems
        }

        if essentialsStoreIsEmpty {
            if layoutItems.isEmpty {
                return [nil]
            }
            return layoutItems
        }

        guard case .essentials(let slot) = dragState.projectionHoveredSlot else {
            return layoutItems
        }

        let safeSlot = max(0, min(slot, layoutItems.count))
        layoutItems.insert(nil, at: safeSlot)
        return layoutItems
    }

    private static func resolvedCapacityColumnCount(
        for width: CGFloat,
        configuration: PinnedTabsConfiguration
    ) -> Int {
        guard width > 0 else { return 1 }

        var columns = maxColumns
        while columns > 1 {
            let neededWidth = CGFloat(columns) * configuration.minWidth
                + CGFloat(columns - 1) * configuration.gridSpacing
            if neededWidth <= width {
                break
            }
            columns -= 1
        }
        return max(1, columns)
    }

    static func visualTileSize(
        width: CGFloat,
        visualColumnCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> CGSize {
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: visualColumnCount,
            configuration: configuration
        )
        return CGSize(width: tileWidth, height: configuration.height)
    }

    private static func resolvedTileWidth(
        width: CGFloat,
        columnCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> CGFloat {
        let columns = max(columnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * configuration.gridSpacing), 0)
        return max(availableWidth / CGFloat(columns), configuration.minWidth)
    }

    static func projectedRows(
        from items: [ShortcutPin?],
        capacityColumnCount: Int,
        width: CGFloat,
        configuration: PinnedTabsConfiguration
    ) -> [SidebarEssentialsProjectedRow] {
        guard !items.isEmpty else { return [] }
        let safeCapacityColumnCount = max(capacityColumnCount, 1)

        return stride(from: 0, to: items.count, by: safeCapacityColumnCount).map { index in
            let rowItems = Array(items[index..<min(index + safeCapacityColumnCount, items.count)])
            let visualColumnCount = max(1, min(rowItems.count, safeCapacityColumnCount))
            let tileSize = visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount,
                configuration: configuration
            )

            return SidebarEssentialsProjectedRow(
                items: rowItems,
                startSlot: index,
                visualColumnCount: visualColumnCount,
                tileSize: tileSize
            )
        }
    }
}
