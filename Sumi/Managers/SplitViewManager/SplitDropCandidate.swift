import CoreGraphics
import Foundation

/// A proposed pointer intent is not publishable until the layout mutation can
/// produce a canonical tree. This value keeps that invariant at one boundary.
struct SplitDropCandidate {
    let target: SplitDropTarget
    let draggedTabId: UUID
    let previewRect: CGRect?

    init(
        target: SplitDropTarget,
        draggedTabId: UUID,
        previewRect: CGRect? = nil
    ) {
        self.target = target
        self.draggedTabId = draggedTabId
        self.previewRect = previewRect
    }

    func resolved(
        in tree: SplitLayoutTree,
        bounds: CGRect
    ) -> SplitDropTarget? {
        guard let resolution = SplitLayoutDropMutation.resolve(
            in: tree,
            draggedTabId: draggedTabId,
            target: target,
            bounds: bounds
        ) else {
            return nil
        }

        guard let previewRect else {
            return resolution.target
        }
        return resolution.target.resolving(
            targetRect: previewRect,
            resolvedLayoutTree: resolution.layoutTree
        )
    }
}
