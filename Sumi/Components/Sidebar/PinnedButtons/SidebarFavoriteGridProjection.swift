//
//  SidebarFavoriteGridProjection.swift
//  Sumi
//

import SwiftUI
import SumiDomain

enum SidebarFavoriteDisplayCell {
    case pin(ShortcutPin)
    case splitGroup(SplitGroup)
    case gap(Int)
    case spacer(Int)

    var stableID: String {
        switch self {
        case .pin(let pin):
            return "pin-\(pin.id.uuidString)"
        case .splitGroup(let group):
            return "split-group-\(group.id.uuidString)"
        case .gap(let slot):
            return "gap-\(slot)"
        case .spacer(let id):
            return "spacer-\(id)"
        }
    }
}

struct SidebarFavoriteDisplayRow {
    let cells: [SidebarFavoriteDisplayCell]
    let tileSize: CGSize
    let startSlot: Int

    var stableID: Int {
        startSlot
    }

    var layoutSignature: [String] {
        cells.map(\.stableID)
    }
}

@MainActor
struct SidebarFavoriteGridProjection {
    let width: CGFloat

    func projectedContentHeight(
        for layout: SidebarFavoriteProjectedLayout
    ) -> CGFloat {
        let rows = max(layout.visibleRowCount, 1)
        return CGFloat(rows) * layout.tileSize.height
            + CGFloat(max(rows - 1, 0)) * PinnedTileMetrics.gridSpacing
    }

    func resolvedDropFrame(
        visibleRowCount: Int,
        maxDropRowCount: Int,
        tileSize: CGSize,
        visibleHeight: CGFloat
    ) -> CGRect {
        let safeVisibleRowCount = max(visibleRowCount, 1)
        let extraRows = max(0, maxDropRowCount - safeVisibleRowCount)
        let extraHeight = CGFloat(extraRows) * (tileSize.height + PinnedTileMetrics.gridSpacing)
        return CGRect(
            x: 0,
            y: 0,
            width: width,
            height: visibleHeight + extraHeight
        )
    }

    func resolvedPreviewState(
        _ previewState: SidebarFavoritePreviewState,
        visibleRowCount: Int,
        maxDropRowCount: Int
    ) -> SidebarFavoritePreviewState? {
        guard maxDropRowCount > visibleRowCount,
              previewState.expandedDropRowCount > visibleRowCount else {
            return nil
        }
        return SidebarFavoritePreviewState(
            expandedDropRowCount: min(previewState.expandedDropRowCount, maxDropRowCount),
            gapSlot: previewState.gapSlot
        )
    }

    func resolvedDisplayRows(
        for layout: SidebarFavoriteProjectedLayout,
        previewState: SidebarFavoritePreviewState?,
        maxDropRowCount: Int
    ) -> [SidebarFavoriteDisplayRow] {
        var rows = layout.rows.map { row in
            let cells = row.items.enumerated().map { offset, item in
                if let item {
                    switch item {
                    case .pin(let pin):
                        return SidebarFavoriteDisplayCell.pin(pin)
                    case .splitGroup(let group):
                        return SidebarFavoriteDisplayCell.splitGroup(group)
                    }
                }
                return .gap(row.startSlot + offset)
            }

            return SidebarFavoriteDisplayRow(
                cells: cells,
                tileSize: row.tileSize,
                startSlot: row.startSlot
            )
        }

        guard let previewState else { return rows }

        let columns = max(layout.capacityColumnCount, 1)
        let targetRowCount = min(
            max(previewState.expandedDropRowCount, rows.count),
            maxDropRowCount
        )
        guard targetRowCount > rows.count else { return rows }

        while rows.count < targetRowCount {
            let rowIndex = rows.count
            let rowStart = rowIndex * columns
            let rowEnd = rowStart + columns
            var cells = [SidebarFavoriteDisplayCell.spacer(rowStart)]
            var visualColumnCount = 1

            if let gapSlot = previewState.gapSlot,
               gapSlot >= rowStart,
               gapSlot < rowEnd {
                let localSlot = gapSlot - rowStart
                visualColumnCount = max(1, min(localSlot + 1, columns))
                cells = (0..<visualColumnCount).map { SidebarFavoriteDisplayCell.spacer(rowStart + $0) }
                cells[localSlot] = .gap(gapSlot)
            }

            let tileSize = SidebarFavoriteProjectionPolicy.visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount
            )
            rows.append(
                SidebarFavoriteDisplayRow(
                    cells: cells,
                    tileSize: tileSize,
                    startSlot: rowStart
                )
            )
        }

        return rows
    }

    func resolvedDropSlotFrames(
        for layout: SidebarFavoriteProjectedLayout,
        revealTileSize: CGSize,
        maxDropRowCount: Int
    ) -> [SidebarFavoriteDropSlotMetrics] {
        guard layout.visibleItemCount > 0 else {
            return [
                SidebarFavoriteDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(origin: .zero, size: revealTileSize)
                ),
            ]
        }

        let maxSlot = min(layout.visibleItemCount, SidebarFavoriteProjectionPolicy.maxItems)
        return (0...maxSlot).compactMap { slot in
            var items = layout.visibleItems
            let safeSlot = max(0, min(slot, items.count))
            items.insert(nil, at: safeSlot)

            let rows = SidebarFavoriteProjectionPolicy.projectedRows(
                from: items,
                capacityColumnCount: layout.capacityColumnCount,
                width: width
            )
            guard let rowIndex = rows.firstIndex(where: { row in
                row.items.contains { item in
                    if case .none = item { return true }
                    return false
                }
            }),
                  rowIndex < max(maxDropRowCount, 1)
            else { return nil }

            let row = rows[rowIndex]
            guard let columnIndex = row.items.firstIndex(where: { item in
                if case .none = item { return true }
                return false
            }) else {
                return nil
            }

            return SidebarFavoriteDropSlotMetrics(
                slot: safeSlot,
                frame: CGRect(
                    x: CGFloat(columnIndex) * (row.tileSize.width + PinnedTileMetrics.gridSpacing),
                    y: CGFloat(rowIndex) * (row.tileSize.height + PinnedTileMetrics.gridSpacing),
                    width: row.tileSize.width,
                    height: row.tileSize.height
                )
            )
        }
    }
}
