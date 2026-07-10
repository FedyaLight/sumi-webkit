import CoreGraphics
import Foundation

struct SplitDropResolutionContext {
    private static let previewPlaceholderTabId = UUID()

    let group: SplitGroup
    let location: CGPoint
    let bounds: CGRect
    let draggedTabId: UUID?
    let previewTabId: UUID
    let draggedTabIsInGroup: Bool
    let leafHit: SplitLayoutGeometry.LeafHit?

    init?(
        group: SplitGroup,
        location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location),
              let canonicalGroup = group.canonicalizedForTiles()
        else {
            return nil
        }

        self.group = canonicalGroup
        self.location = location
        self.bounds = bounds
        self.draggedTabId = draggedTabId
        previewTabId = draggedTabId ?? Self.previewPlaceholderTabId
        draggedTabIsInGroup = draggedTabId.map(canonicalGroup.contains) ?? false
        leafHit = SplitLayoutGeometry.leafHit(
            in: canonicalGroup.layoutTree,
            at: location,
            in: bounds
        )
    }

    var canInsertAtEdge: Bool {
        draggedTabIsInGroup || group.tabIds.count < SplitGroup.maximumTabs
    }
}
