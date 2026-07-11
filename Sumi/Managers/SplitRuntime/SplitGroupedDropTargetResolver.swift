import CoreGraphics
import Foundation
import SumiDomain

struct SplitGroupedDropTargetResolver {
    func target(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedMember: SplitMember?,
        fullGroupLayouts: inout SplitFullGroupLayoutCatalog
    ) -> SplitDropTarget? {
        guard let context = SplitDropResolutionContext(
            group: group,
            location: location,
            bounds: bounds,
            draggedMember: draggedMember
        ) else {
            return nil
        }

        if context.draggedMemberIsInGroup,
           context.group.memberIDs.count == SplitGroup.maximumMembers,
           SplitDropLayoutEligibility.flatAxis(
               in: context.group.layoutTree,
               childCount: SplitGroup.maximumMembers
           ) != nil {
            return SplitFullGroupDropResolver.flatLineTarget(in: context)
        }

        if context.canInsertAtEdge {
            if let target = SplitDropPairingResolver.flatThreeTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver
                .leafLocalOrthogonalTarget(in: context) {
                return target
            }
            if let target = SplitDropPairingResolver
                .mixedThreeOneTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver
                .parentSiblingTarget(in: context) {
                return target
            }
            if let target = SplitFullGroupDropResolver.panePairTarget(
                in: context,
                layouts: &fullGroupLayouts
            ) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver
                .rootOrPlaneTarget(in: context) {
                return target
            }
            if let target = SplitDropEdgeInsertionResolver
                .siblingTarget(in: context) {
                return target
            }
        }

        return centerReplacementTarget(in: context)
    }

    private func centerReplacementTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard !context.draggedMemberIsInGroup,
              let hit = context.leafHit,
              SplitDropEdgeHitPolicy.side(
                  at: context.location,
                  in: hit.rect,
                  mode: .rearrange
              ) == .center else {
            return nil
        }

        return SplitDropCandidate(
            target: SplitDropTarget(
                targetMemberID: hit.memberID,
                side: .center,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .center,
                planePath: hit.path,
                intent: .paneCenter
            ),
            draggedMember: context.previewMember
        ).resolved(in: context.group.layoutTree, bounds: context.bounds)
    }
}
