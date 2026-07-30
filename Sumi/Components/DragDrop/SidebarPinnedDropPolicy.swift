import CoreGraphics
import Foundation
import SumiDomain

struct SidebarPinnedDropContext {
    let page: SidebarPageGeometryMetrics
    let sectionFrame: CGRect
    let essentialsBoundaryY: CGFloat
    let topLevelItems: [SidebarTopLevelPinnedItemMetrics]
    let listMetrics: SidebarPinnedListHitMetrics?
    let hasFolderTargets: Bool
    let draggedItem: SumiDragItem?
}

enum SidebarPinnedDropPolicy {
    private static let topEdgeAllowance = SidebarRowLayout.rowHeight

    static func resolve(
        location: CGPoint,
        context: SidebarPinnedDropContext
    ) -> SidebarDropResolution? {
        guard hitFrame(context).contains(location),
              location.y >= context.essentialsBoundaryY else { return nil }

        if let metrics = context.listMetrics {
            return resolution(
                spaceID: context.page.spaceId,
                slot: metrics.rowBoundaryIndex(forGlobalY: location.y)
            )
        }
        if context.topLevelItems.isEmpty == false,
           let slot = topLevelSlot(
               location: location,
               items: context.topLevelItems
           ) {
            if context.draggedItem?.kind == .folder,
               let directItem = context.topLevelItems.first(where: {
                   $0.frame.contains(location)
               }),
               directItem.itemId == context.draggedItem?.tabId {
                return .empty
            }
            return resolution(spaceID: context.page.spaceId, slot: slot)
        }
        guard context.hasFolderTargets == false else { return nil }
        return resolution(
            spaceID: context.page.spaceId,
            slot: SidebarDropSlotPolicy.midpointIndex(
                localY: max(0, location.y - context.sectionFrame.minY)
            )
        )
    }

    private static func hitFrame(_ context: SidebarPinnedDropContext) -> CGRect {
        let frame = context.sectionFrame
        let topY = max(
            context.page.frame.minY,
            frame.minY - topEdgeAllowance
        )
        let maxY = max(
            frame.maxY,
            frame.minY + SidebarRowLayout.rowHeight
        )
        return CGRect(
            x: frame.minX,
            y: topY,
            width: frame.width,
            height: max(0, maxY - topY)
        )
    }

    private static func topLevelSlot(
        location: CGPoint,
        items: [SidebarTopLevelPinnedItemMetrics]
    ) -> Int? {
        guard let first = items.first, let last = items.last else { return 0 }
        if location.y < first.frame.minY { return first.topLevelIndex }
        for item in items where item.frame.contains(location) {
            return location.y < item.frame.midY
                ? item.topLevelIndex
                : item.topLevelIndex + 1
        }
        for (previous, next) in zip(items, items.dropFirst())
            where location.y >= previous.frame.maxY
                && location.y < next.frame.minY {
            return location.y
                < (previous.frame.maxY + next.frame.minY) / 2
                ? previous.topLevelIndex + 1
                : next.topLevelIndex
        }
        if location.y >= last.frame.maxY {
            return last.topLevelIndex + 1
        }
        guard let nearest = items.min(by: { lhs, rhs in
            abs(location.y - lhs.frame.midY)
                < abs(location.y - rhs.frame.midY)
        }) else { return nil }
        return location.y < nearest.frame.midY
            ? nearest.topLevelIndex
            : nearest.topLevelIndex + 1
    }

    private static func resolution(
        spaceID: UUID,
        slot: Int
    ) -> SidebarDropResolution {
        SidebarDropResolution(
            slot: .spacePinned(spaceId: spaceID, slot: slot),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }
}
