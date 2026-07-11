import CoreGraphics
import Foundation
import SumiDomain

/// A pointer intent is publishable only after it produces a canonical durable
/// tree. The candidate carries the whole incoming member, never a runtime tab.
struct SplitDropCandidate {
    let target: SplitDropTarget
    let draggedMember: SplitMember
    let previewRect: CGRect?

    init(
        target: SplitDropTarget,
        draggedMember: SplitMember,
        previewRect: CGRect? = nil
    ) {
        self.target = target
        self.draggedMember = draggedMember
        self.previewRect = previewRect
    }

    func resolved(
        in tree: SplitLayoutTree,
        bounds: CGRect
    ) -> SplitDropTarget? {
        guard let resolution = SplitLayoutDropMutation.resolve(
            in: tree,
            draggedMember: draggedMember,
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
