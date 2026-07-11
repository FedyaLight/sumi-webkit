import SumiDomain

enum SplitFullGroupDropResolver {
    static func panePairTarget(
        in context: SplitDropResolutionContext,
        layouts: inout SplitFullGroupLayoutCatalog
    ) -> SplitDropTarget? {
        guard let draggedMember = context.draggedMember,
              context.draggedMemberIsInGroup,
              context.group.memberIDs.count == SplitGroup.maximumMembers,
              let hit = context.leafHit,
              hit.memberID != draggedMember.memberID else {
            return nil
        }

        for side in SplitDropTargetGeometry.rankedEdgeSides(
            at: context.location,
            in: hit.rect
        ) {
            guard let insertionAxis = side.insertionAxis,
                  SplitDropLayoutEligibility.parentAxis(
                      for: hit.path,
                      in: context.group.layoutTree
                  ) != insertionAxis else {
                continue
            }

            let previewRect = SplitDropTargetGeometry.halfRect(
                for: side,
                in: hit.rect
            )
            guard let resolvedTree = SplitFullGroupPairRanker.bestTree(
                among: layouts.trees(for: context.group.members),
                preserving: context.group.layoutTree,
                draggedMemberID: draggedMember.memberID,
                targetMemberID: hit.memberID,
                side: side,
                desiredRect: previewRect,
                bounds: context.bounds
            ) else {
                continue
            }

            let target = SplitDropTarget(
                targetMemberID: hit.memberID,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .fullGroupPanePair,
                resolvedLayoutTree: resolvedTree
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

    static func flatLineTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedMember = context.draggedMember,
              context.draggedMemberIsInGroup,
              context.group.memberIDs.count == SplitGroup.maximumMembers,
              let flatAxis = SplitDropLayoutEligibility.flatAxis(
                  in: context.group.layoutTree,
                  childCount: SplitGroup.maximumMembers
              ),
              let hit = context.leafHit else {
            return nil
        }

        for side in SplitDropTargetGeometry.rankedEdgeSides(
            at: context.location,
            in: hit.rect
        ) {
            guard let insertionAxis = side.insertionAxis else { continue }

            if insertionAxis == flatAxis {
                guard hit.memberID != draggedMember.memberID else { continue }
                let target = SplitDropTarget(
                    targetMemberID: hit.memberID,
                    side: side,
                    targetRect: hit.rect,
                    scope: .pane,
                    previewStyle: .edge,
                    planePath: hit.path,
                    intent: .flatFourReorder
                )
                if let resolved = SplitDropCandidate(
                    target: target,
                    draggedMember: draggedMember
                ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                    return resolved
                }
                continue
            }

            if hit.memberID == draggedMember.memberID {
                let target = SplitDropTarget(
                    targetMemberID: hit.memberID,
                    side: side,
                    targetRect: context.bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                if let resolved = SplitDropCandidate(
                    target: target,
                    draggedMember: draggedMember
                ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                    return resolved
                }
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
                intent: .flatFourPair
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedMember: draggedMember,
                previewRect: previewRect
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }

        guard hit.memberID != draggedMember.memberID,
              let middleSide = SplitDropTargetGeometry.middleRootSide(
                  for: flatAxis,
                  at: context.location,
                  in: hit.rect
              ) else {
            return nil
        }

        return SplitDropCandidate(
            target: SplitDropTarget(
                targetMemberID: hit.memberID,
                side: middleSide,
                targetRect: context.bounds,
                scope: .group,
                previewStyle: .edge,
                planePath: [],
                intent: .rootEdge
            ),
            draggedMember: draggedMember
        ).resolved(in: context.group.layoutTree, bounds: context.bounds)
    }
}
