import CoreGraphics
import Foundation

/// Pure math for the drop-indicator line: maps a resolved drop slot onto a
/// line rect in geometry space (scroll-normalized SwiftUI `.global`).
/// Returns `nil` whenever the line must stay hidden — essentials keep their
/// grid slot preview, folder "contain" hovers show the folder highlight, and
/// empty pinned sections show the reveal strip instead.
enum SidebarDropIndicatorGeometry {
    enum Metrics {
        static let lineHeight: CGFloat = 2
        static let cornerRadius: CGFloat = 1
        static let horizontalInset: CGFloat = 4
        static let ringDiameter: CGFloat = 8
        static let ringBorderWidth: CGFloat = 2
        /// Slide duration for the line moving between slots (Zen: 50ms ease-out).
        static let slideDuration: TimeInterval = 0.07
    }

    static func lineRect(
        slot: DropZoneSlot,
        folderIntent: FolderDropIntent,
        geometry: SidebarGeometrySnapshot
    ) -> CGRect? {
        if case .contain = folderIntent {
            return nil
        }

        switch slot {
        case .empty, .essentials:
            return nil
        case .spaceRegular(let spaceId, let slotIndex):
            return regularLineRect(
                spaceId: spaceId,
                slotIndex: slotIndex,
                geometry: geometry
            )
        case .spacePinned(let spaceId, let slotIndex):
            if let metrics = geometry.pinnedListHitTargets[spaceId] {
                return lineRect(
                    atBoundaryY: metrics.boundaryY(for: slotIndex),
                    container: metrics.rowsFrame
                )
            }
            return boundaryLineRect(
                slotIndex: slotIndex,
                itemFrames: (geometry.hitTestIndex.topLevelPinnedItemsBySpace[spaceId] ?? [])
                    .map(\.frame)
            )
        case .folder(let folderId, let slotIndex):
            return folderLineRect(
                folderId: folderId,
                slotIndex: slotIndex,
                geometry: geometry
            )
        }
    }

    // MARK: - Sections

    private static func regularLineRect(
        spaceId: UUID,
        slotIndex: Int,
        geometry: SidebarGeometrySnapshot
    ) -> CGRect? {
        guard let metrics = geometry.regularListHitTargets[spaceId] else {
            return nil
        }
        guard metrics.rowCount > 0 else {
            return lineRect(atBoundaryY: metrics.frame.minY, container: metrics.frame)
        }

        let boundaryIndex = max(0, min(slotIndex, metrics.rowCount))
        let rowSpacing = metrics.rowPitch - SidebarRowLayout.rowHeight

        let boundaryY: CGFloat
        switch boundaryIndex {
        case 0:
            boundaryY = metrics.frame.minY
        case metrics.rowCount:
            boundaryY = metrics.frame.maxY
        default:
            // Interior boundary: center of the spacing gap above the row.
            boundaryY = metrics.frame.minY
                + CGFloat(boundaryIndex) * metrics.rowPitch
                - rowSpacing / 2
        }
        return lineRect(atBoundaryY: boundaryY, container: metrics.frame)
    }

    private static func folderLineRect(
        folderId: UUID,
        slotIndex: Int,
        geometry: SidebarGeometrySnapshot
    ) -> CGRect? {
        let childFrames = (geometry.hitTestIndex.folderChildrenByFolder[folderId] ?? [])
            .map(\.frame)
        if let rect = boundaryLineRect(slotIndex: slotIndex, itemFrames: childFrames) {
            return rect
        }

        // Open empty folder: point at the top of its (possibly zero-height) body.
        guard let bodyFrame = geometry.folderDropTargets[folderId]?.bodyFrame else {
            return nil
        }
        return lineRect(atBoundaryY: bodyFrame.minY, container: bodyFrame)
    }

    // MARK: - Shared boundary math

    /// Boundary line for insertion slot `slotIndex` in a run of per-item frames
    /// (sorted top to bottom, variable heights allowed — pinned rows can be
    /// open folders). Returns `nil` when there are no frames to anchor to.
    private static func boundaryLineRect(
        slotIndex: Int,
        itemFrames: [CGRect]
    ) -> CGRect? {
        guard let firstFrame = itemFrames.first,
              let lastFrame = itemFrames.last else {
            return nil
        }

        let safeSlot = max(0, min(slotIndex, itemFrames.count))
        let boundaryY: CGFloat
        let container: CGRect
        switch safeSlot {
        case 0:
            boundaryY = firstFrame.minY
            container = firstFrame
        case itemFrames.count:
            boundaryY = lastFrame.maxY
            container = lastFrame
        default:
            let above = itemFrames[safeSlot - 1]
            let below = itemFrames[safeSlot]
            boundaryY = (above.maxY + below.minY) / 2
            container = below
        }
        return lineRect(atBoundaryY: boundaryY, container: container)
    }

    private static func lineRect(
        atBoundaryY boundaryY: CGFloat,
        container: CGRect
    ) -> CGRect {
        CGRect(
            x: container.minX + Metrics.horizontalInset,
            y: boundaryY - Metrics.lineHeight / 2,
            width: max(0, container.width - Metrics.horizontalInset * 2),
            height: Metrics.lineHeight
        )
    }
}
