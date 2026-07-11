import Foundation
import SumiDomain

enum SplitDropPairingResolver {
    static func flatThreeTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedMember = context.draggedMember,
              context.group.memberIDs.count == 3,
              let flatAxis = SplitDropLayoutEligibility.flatAxis(
                  in: context.group.layoutTree,
                  childCount: 3
              ),
              let hit = context.leafHit,
              hit.memberID != draggedMember.memberID,
              !SplitDropTargetGeometry.isNearInternalDivider(
                  location: context.location,
                  leafRect: hit.rect,
                  bounds: context.bounds,
                  rootAxis: flatAxis
              ) else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(
            at: context.location,
            in: hit.rect,
            mode: .create
        ) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != flatAxis else {
                continue
            }

            let previewRect = SplitDropTargetGeometry.halfRect(
                for: side,
                in: hit.rect
            )
            let target = SplitDropTarget(
                targetMemberID: hit.memberID,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatThreePair
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedMember: draggedMember,
                previewRect: previewRect
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }
        return nil
    }

    static func mixedThreeOneTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedMember = context.draggedMember,
              context.draggedMemberIsInGroup,
              context.group.memberIDs.count == SplitGroup.maximumMembers,
              let structure = SplitDropLayoutEligibility.mixedThreeOne(
                  in: context.group.layoutTree
              ),
              let hit = context.leafHit,
              hit.memberID != draggedMember.memberID,
              structure.canPair(
                  draggedMemberID: draggedMember.memberID,
                  targetMemberID: hit.memberID
              ) else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(
            at: context.location,
            in: hit.rect,
            mode: .create
        ) where side.insertionAxis != nil {
            let previewRect = SplitDropTargetGeometry.halfRect(
                for: side,
                in: hit.rect
            )
            let target = SplitDropTarget(
                targetMemberID: hit.memberID,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .mixedThreeOnePair
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedMember: draggedMember,
                previewRect: previewRect
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }
        return nil
    }
}
