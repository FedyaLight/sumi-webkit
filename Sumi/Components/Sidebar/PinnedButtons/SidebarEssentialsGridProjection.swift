//
//  SidebarEssentialsGridProjection.swift
//  Sumi
//

import SwiftUI

enum SidebarEssentialsDisplayCell {
    case pin(ShortcutPin)
    case gap(Int)
    case spacer(Int)

    var stableID: String {
        switch self {
        case .pin(let pin):
            return "pin-\(pin.id.uuidString)"
        case .gap(let slot):
            return "gap-\(slot)"
        case .spacer(let id):
            return "spacer-\(id)"
        }
    }
}

struct SidebarEssentialsDisplayRow {
    let cells: [SidebarEssentialsDisplayCell]
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
struct SidebarEssentialsGridProjection {
    let width: CGFloat
    let configuration: PinnedTabsConfiguration

    func projectedContentHeight(
        for layout: SidebarEssentialsProjectedLayout
    ) -> CGFloat {
        let rows = max(layout.visibleRowCount, 1)
        return CGFloat(rows) * layout.tileSize.height
            + CGFloat(max(rows - 1, 0)) * configuration.gridSpacing
    }

    func resolvedDropFrame(
        visibleRowCount: Int,
        maxDropRowCount: Int,
        tileSize: CGSize,
        visibleHeight: CGFloat
    ) -> CGRect {
        let safeVisibleRowCount = max(visibleRowCount, 1)
        let extraRows = max(0, maxDropRowCount - safeVisibleRowCount)
        let extraHeight = CGFloat(extraRows) * (tileSize.height + configuration.gridSpacing)
        return CGRect(
            x: 0,
            y: 0,
            width: width,
            height: visibleHeight + extraHeight
        )
    }

    func resolvedPreviewState(
        _ previewState: SidebarEssentialsPreviewState,
        visibleRowCount: Int,
        maxDropRowCount: Int
    ) -> SidebarEssentialsPreviewState? {
        guard maxDropRowCount > visibleRowCount,
              previewState.expandedDropRowCount > visibleRowCount else {
            return nil
        }
        return SidebarEssentialsPreviewState(
            expandedDropRowCount: min(previewState.expandedDropRowCount, maxDropRowCount),
            gapSlot: previewState.gapSlot
        )
    }

    func resolvedDisplayRows(
        for layout: SidebarEssentialsProjectedLayout,
        previewState: SidebarEssentialsPreviewState?,
        maxDropRowCount: Int
    ) -> [SidebarEssentialsDisplayRow] {
        var rows = layout.rows.map { row in
            let cells = row.items.enumerated().map { offset, item in
                if let item {
                    return SidebarEssentialsDisplayCell.pin(item)
                }
                return .gap(row.startSlot + offset)
            }

            return SidebarEssentialsDisplayRow(
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
            var cells = [SidebarEssentialsDisplayCell.spacer(rowStart)]
            var visualColumnCount = 1

            if let gapSlot = previewState.gapSlot,
               gapSlot >= rowStart,
               gapSlot < rowEnd {
                let localSlot = gapSlot - rowStart
                visualColumnCount = max(1, min(localSlot + 1, columns))
                cells = (0..<visualColumnCount).map { SidebarEssentialsDisplayCell.spacer(rowStart + $0) }
                cells[localSlot] = .gap(gapSlot)
            }

            let tileSize = SidebarEssentialsProjectionPolicy.visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount,
                configuration: configuration
            )
            rows.append(
                SidebarEssentialsDisplayRow(
                    cells: cells,
                    tileSize: tileSize,
                    startSlot: rowStart
                )
            )
        }

        return rows
    }

    func resolvedDropSlotFrames(
        for layout: SidebarEssentialsProjectedLayout,
        revealTileSize: CGSize,
        maxDropRowCount: Int
    ) -> [SidebarEssentialsDropSlotMetrics] {
        guard layout.visibleItemCount > 0 else {
            return [
                SidebarEssentialsDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(origin: .zero, size: revealTileSize)
                )
            ]
        }

        let maxSlot = min(layout.visibleItemCount, SidebarEssentialsProjectionPolicy.maxItems)
        return (0...maxSlot).compactMap { slot in
            var items = layout.visibleItems
            let safeSlot = max(0, min(slot, items.count))
            items.insert(nil, at: safeSlot)

            let rows = SidebarEssentialsProjectionPolicy.projectedRows(
                from: items,
                capacityColumnCount: layout.capacityColumnCount,
                width: width,
                configuration: configuration
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

            return SidebarEssentialsDropSlotMetrics(
                slot: safeSlot,
                frame: CGRect(
                    x: CGFloat(columnIndex) * (row.tileSize.width + configuration.gridSpacing),
                    y: CGFloat(rowIndex) * (row.tileSize.height + configuration.gridSpacing),
                    width: row.tileSize.width,
                    height: row.tileSize.height
                )
            )
        }
    }
}
