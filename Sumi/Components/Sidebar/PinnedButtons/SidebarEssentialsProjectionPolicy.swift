//
//  SidebarEssentialsProjectionPolicy.swift
//  Sumi
//

import SwiftUI
import SumiDomain

enum SidebarEssentialVisualItem {
    case pin(ShortcutPin)
    case splitGroup(SplitGroup)

    var id: UUID {
        switch self {
        case .pin(let pin): pin.id
        case .splitGroup(let group): group.id
        }
    }
}

@MainActor
enum SidebarEssentialVisualProjection {
    static func make(
        pins: [ShortcutPin],
        splitGroups: [SplitGroup],
        profileID: UUID?
    ) -> [SidebarEssentialVisualItem] {
        let pinsByID = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
        let groupsByID = Dictionary(
            uniqueKeysWithValues: splitGroups.map { ($0.id, $0) }
        )
        return SidebarVisualOrdering.essentialItems(
            pins: pins,
            groups: splitGroups,
            profileID: profileID
        ).compactMap { item in
            switch item {
            case .shortcut(let pinID):
                return pinsByID[pinID].map(SidebarEssentialVisualItem.pin)
            case .splitGroup(let groupID):
                return groupsByID[groupID].map(
                    SidebarEssentialVisualItem.splitGroup
                )
            case .folder:
                return nil
            }
        }
    }
}

struct SidebarEssentialsProjectedRow {
    let items: [SidebarEssentialVisualItem?]
    let startSlot: Int
    let visualColumnCount: Int
    let tileSize: CGSize
}

struct SidebarEssentialsProjectedLayout {
    let layoutItems: [SidebarEssentialVisualItem?]
    let visibleItems: [SidebarEssentialVisualItem?]
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
    static let maxColumns = EssentialsShortcutPlacementOwner.CapacityPolicy.maxColumns
    static let maxRows = EssentialsShortcutPlacementOwner.CapacityPolicy.maxRows
    static let maxItems = maxColumns * maxRows

    static func make(
        items: [SidebarEssentialVisualItem],
        width: CGFloat,
        dragPresentation: SidebarEssentialsDragPresentationFrame
    ) -> SidebarEssentialsProjectedLayout {
        let baseVisibleItems = resolvedVisibleItems(
            from: items,
            dragPresentation: dragPresentation
        )
        let canAcceptDrop = baseVisibleItems.count < maxItems
        let layoutItems = resolvedLayoutItems(
            from: baseVisibleItems,
            dragPresentation: dragPresentation,
            canAcceptDrop: canAcceptDrop,
            essentialsStoreIsEmpty: items.isEmpty
        )
        let capacityColumnCount = resolvedCapacityColumnCount(for: width)
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: capacityColumnCount
        )
        let tileSize = CGSize(width: tileWidth, height: PinnedTileMetrics.height)

        return SidebarEssentialsProjectedLayout(
            layoutItems: layoutItems,
            visibleItems: baseVisibleItems,
            capacityColumnCount: capacityColumnCount,
            tileSize: tileSize,
            rows: projectedRows(
                from: layoutItems,
                capacityColumnCount: capacityColumnCount,
                width: width
            ),
            visibleRows: projectedRows(
                from: baseVisibleItems,
                capacityColumnCount: capacityColumnCount,
                width: width
            ),
            canAcceptDrop: canAcceptDrop
        )
    }

    static func projectedCountAfterDrop(
        itemIDs: [UUID],
        visibleItemCount: Int,
        layoutItemCount: Int,
        canAcceptDrop: Bool,
        dragPresentation: SidebarEssentialsDragPresentationFrame
    ) -> Int {
        let safeVisibleItemCount = max(visibleItemCount, 0)
        guard canAcceptDrop else { return min(safeVisibleItemCount, maxItems) }

        let isDraggingExistingEssential = dragPresentation.projectionDragItemID
            .map { itemIDs.contains($0) } ?? false
        let isHoveringEssentials = {
            guard dragPresentation.isDropProjectionActive,
                  case .essentials = dragPresentation.projectionHoveredSlot else {
                return false
            }
            return true
        }()

        let emptyStorePlaceholderActive = dragPresentation.isDropProjectionActive
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
        dragPresentation: SidebarEssentialsDragPresentationFrame
    ) -> Int {
        let projectedCount = projectedCountAfterDrop(
            itemIDs: itemIDs,
            visibleItemCount: visibleItemCount,
            layoutItemCount: layoutItemCount,
            canAcceptDrop: canAcceptDrop,
            dragPresentation: dragPresentation
        )
        let safeColumnCount = max(columnCount, 1)
        return min(
            maxRows,
            max(1, Int(ceil(Double(max(projectedCount, 1)) / Double(safeColumnCount))))
        )
    }

    private static func resolvedVisibleItems(
        from items: [SidebarEssentialVisualItem],
        dragPresentation: SidebarEssentialsDragPresentationFrame
    ) -> [SidebarEssentialVisualItem?] {
        guard let projectionDragItemID = dragPresentation.projectionDragItemID else {
            return items.map { Optional($0) }
        }

        let isDraggingExistingEssential: Bool = {
            guard dragPresentation.isDropProjectionActive,
                  dragPresentation.projectionDragScope?.sourceContainer == .essentials else {
                return false
            }
            return items.contains { $0.id == projectionDragItemID }
        }()

        return items.compactMap { item -> SidebarEssentialVisualItem? in
            if item.id == projectionDragItemID, isDraggingExistingEssential {
                return nil
            }
            return item
        }
    }

    private static func resolvedLayoutItems(
        from items: [SidebarEssentialVisualItem?],
        dragPresentation: SidebarEssentialsDragPresentationFrame,
        canAcceptDrop: Bool,
        essentialsStoreIsEmpty: Bool
    ) -> [SidebarEssentialVisualItem?] {
        var layoutItems = items

        guard dragPresentation.isDropProjectionActive, canAcceptDrop else {
            return layoutItems
        }

        if let projectionDragItemID = dragPresentation.projectionDragItemID,
           dragPresentation.shouldHideCommittedCrossContainerPlaceholder(
                into: .essentials,
                targetAlreadyContainsDraggedItem: items.contains { $0?.id == projectionDragItemID }
           ) {
            return layoutItems
        }

        if essentialsStoreIsEmpty {
            if layoutItems.isEmpty {
                return [nil]
            }
            return layoutItems
        }

        guard case .essentials(let slot) = dragPresentation.projectionHoveredSlot else {
            return layoutItems
        }

        let safeSlot = max(0, min(slot, layoutItems.count))
        layoutItems.insert(nil, at: safeSlot)
        return layoutItems
    }

    static func resolvedCapacityColumnCount(
        for width: CGFloat
    ) -> Int {
        guard width > 0 else { return 1 }

        var columns = maxColumns
        while columns > 1 {
            let neededWidth = CGFloat(columns) * PinnedTileMetrics.minWidth
                + CGFloat(columns - 1) * PinnedTileMetrics.gridSpacing
            if neededWidth <= width {
                break
            }
            columns -= 1
        }
        return max(1, columns)
    }

    static func visualTileSize(
        width: CGFloat,
        visualColumnCount: Int
    ) -> CGSize {
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: visualColumnCount
        )
        return CGSize(width: tileWidth, height: PinnedTileMetrics.height)
    }

    private static func resolvedTileWidth(
        width: CGFloat,
        columnCount: Int
    ) -> CGFloat {
        let columns = max(columnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * PinnedTileMetrics.gridSpacing), 0)
        return max(availableWidth / CGFloat(columns), PinnedTileMetrics.minWidth)
    }

    static func projectedRows(
        from items: [SidebarEssentialVisualItem?],
        capacityColumnCount: Int,
        width: CGFloat
    ) -> [SidebarEssentialsProjectedRow] {
        guard !items.isEmpty else { return [] }
        let safeCapacityColumnCount = max(capacityColumnCount, 1)

        return stride(from: 0, to: items.count, by: safeCapacityColumnCount).map { index in
            let rowItems = Array(items[index..<min(index + safeCapacityColumnCount, items.count)])
            let visualColumnCount = max(1, min(rowItems.count, safeCapacityColumnCount))
            let tileSize = visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount
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
