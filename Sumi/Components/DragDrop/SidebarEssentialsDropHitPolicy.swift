//
//  SidebarEssentialsDropHitPolicy.swift
//  Sumi
//

import CoreGraphics

/// Resolves the rect a drag must be inside to target the Essentials zone.
///
/// Kept a pure function called once per geometry rebuild instead of a computed
/// property on `SidebarEssentialsLayoutMetrics`: the drop resolver hit-tests the
/// zone on every `draggingUpdated`, and geometry only changes when the reported
/// layout signature does, so the union work belongs on the write side.
enum SidebarEssentialsDropHitPolicy {
    /// An empty zone showing no placeholder collapses to a strip too thin to aim
    /// at, so its hit region widens to at least one tile. With the placeholder on
    /// screen `dropFrame` is already that large and the union is a no-op.
    static func resolvedDropHitFrame(
        frame: CGRect,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics],
        visibleItemCount: Int,
        itemSize: CGSize,
        canAcceptDrop: Bool
    ) -> CGRect {
        guard visibleItemCount == 0, canAcceptDrop else {
            return dropFrame
        }

        let minimumEmptyFrame = CGRect(
            x: dropFrame.minX,
            y: dropFrame.minY,
            width: max(dropFrame.width, frame.width, itemSize.width),
            height: max(dropFrame.height, itemSize.height)
        )
        return dropSlotFrames.reduce(dropFrame.union(minimumEmptyFrame)) { partial, slot in
            partial.union(slot.frame)
        }
    }
}
