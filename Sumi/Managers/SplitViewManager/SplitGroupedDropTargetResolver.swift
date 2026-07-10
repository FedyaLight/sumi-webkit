import CoreGraphics
import Foundation

struct SplitGroupedDropTargetResolver {
    func target(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?,
        fullGroupLayouts: inout SplitFullGroupLayoutCatalog
    ) -> SplitDropTarget? {
        guard let context = SplitDropResolutionContext(
            group: group,
            location: location,
            bounds: bounds,
            draggedTabId: draggedTabId
        ) else {
            return nil
        }

        if context.draggedTabIsInGroup,
           context.group.tabIds.count == SplitGroup.maximumTabs,
           SplitDropLayoutEligibility.flatAxis(
               in: context.group.layoutTree,
               childCount: SplitGroup.maximumTabs
           ) != nil {
            return SplitFullGroupDropResolver.flatLineTarget(in: context)
        }

        if context.canInsertAtEdge {
            if let target = SplitDropPairingResolver.flatThreeTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver.leafLocalOrthogonalTarget(
                in: context
            ) {
                return target
            }
            if let target = SplitDropPairingResolver.mixedThreeOneTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver.parentSiblingTarget(
                in: context
            ) {
                return target
            }
            if let target = SplitFullGroupDropResolver.panePairTarget(
                in: context,
                layouts: &fullGroupLayouts
            ) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver.rootOrPlaneTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver.siblingTarget(in: context) {
                return target
            }
        }

        return centerReplacementTarget(in: context)
    }

    private func centerReplacementTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard context.draggedTabIsInGroup == false,
              let hit = context.leafHit,
              SplitDropCaptureHitPolicy.side(
                  at: context.location,
                  in: hit.rect,
                  mode: .rearrange
              ) == .center
        else {
            return nil
        }

        return SplitDropCandidate(
            target: SplitDropTarget(
                tabId: hit.tabId,
                side: .center,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .center,
                planePath: hit.path,
                intent: .paneCenter
            ),
            draggedTabId: context.previewTabId
        ).resolved(in: context.group.layoutTree, bounds: context.bounds)
    }
}
