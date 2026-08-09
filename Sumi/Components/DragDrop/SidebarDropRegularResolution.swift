import CoreGraphics
import Foundation
import SumiDomain

struct SidebarRegularDropContext {
    let spaceID: UUID
    let outerFrame: CGRect?
    let listMetrics: SidebarRegularListHitMetrics?
}

enum SidebarRegularDropPolicy {
    static func resolve(
        location: CGPoint,
        context: SidebarRegularDropContext
    ) -> SidebarDropResolution? {
        let slot = resolveSlot(location: location, context: context)
        if slot != .empty {
            return SidebarDropResolution(
                slot: slot,
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: context.listMetrics?
                    .presentedBoundary(at: slot.visualIndex)
            )
        }

        if let outerFrame = context.outerFrame,
           location.x >= outerFrame.minX,
           location.x <= outerFrame.maxX,
           location.y >= outerFrame.maxY {
            return SidebarDropResolution(
                slot: .spaceRegular(spaceId: context.spaceID, slot: 9999),
                folderIntent: .none,
                activeHoveredFolderId: nil,
                presentedRegularBoundary: context.listMetrics?
                    .presentedBoundary(at: context.listMetrics?.rowCount ?? 0)
            )
        }
        return nil
    }

    private static func resolveSlot(
        location: CGPoint,
        context: SidebarRegularDropContext
    ) -> DropZoneSlot {
        guard let outerFrame = context.outerFrame else { return .empty }
        guard let metrics = context.listMetrics else {
            guard outerFrame.contains(location) else { return .empty }
            return .spaceRegular(
                spaceId: context.spaceID,
                slot: SidebarDropSlotPolicy.midpointIndex(
                    localY: max(0, location.y - outerFrame.minY)
                )
            )
        }
        guard outerFrame.contains(location) else { return .empty }
        if location.y < metrics.frame.minY {
            return .spaceRegular(spaceId: context.spaceID, slot: 0)
        }
        guard metrics.rowCount > 0 else {
            return .spaceRegular(spaceId: context.spaceID, slot: 0)
        }
        if location.y <= metrics.frame.maxY {
            return .spaceRegular(
                spaceId: context.spaceID,
                slot: metrics.rowBoundaryIndex(
                    forLocalY: max(0, location.y - metrics.frame.minY)
                )
            )
        }
        return .spaceRegular(spaceId: context.spaceID, slot: metrics.rowCount)
    }
}

enum SidebarFavoriteDropPolicy {
    static func resolve(
        location: CGPoint,
        metrics: SidebarFavoriteLayoutMetrics
    ) -> SidebarDropResolution {
        guard metrics.visibleItemCount > 0 else {
            return SidebarDropResolution(
                slot: .favorite(slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }
        let slot = resolvedSlot(location: location, metrics: metrics)
        return SidebarDropResolution(
            slot: .favorite(slot: slot),
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolvedSlot(
        location: CGPoint,
        metrics: SidebarFavoriteLayoutMetrics
    ) -> Int {
        if let containingSlot = metrics.dropSlotFrames.first(where: {
            $0.frame.contains(location)
        }) {
            return max(0, min(containingSlot.slot, metrics.visibleItemCount))
        }
        guard let nearestSlot = metrics.dropSlotFrames.min(by: { lhs, rhs in
            squaredDistance(from: location, to: lhs.frame)
                < squaredDistance(from: location, to: rhs.frame)
        }) else { return 0 }
        return max(0, min(nearestSlot.slot, metrics.visibleItemCount))
    }

    private static func squaredDistance(
        from point: CGPoint,
        to rect: CGRect
    ) -> CGFloat {
        let dx = point.x < rect.minX
            ? rect.minX - point.x
            : point.x > rect.maxX ? point.x - rect.maxX : 0
        let dy = point.y < rect.minY
            ? rect.minY - point.y
            : point.y > rect.maxY ? point.y - rect.maxY : 0
        return (dx * dx) + (dy * dy)
    }
}

enum SidebarDropSlotPolicy {
    static let rowStride: CGFloat = SidebarRowLayout.rowHeight

    static func midpointIndex(localY: CGFloat, itemCount: Int? = nil) -> Int {
        let rawIndex = Int(floor((localY / rowStride) + 0.5))
        guard let itemCount else { return max(0, rawIndex) }
        return max(0, min(rawIndex, itemCount))
    }
}
