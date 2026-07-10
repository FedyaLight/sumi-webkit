import Foundation

enum SplitDropEdgeInsertionResolver {
    static func leafLocalOrthogonalTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard context.group.tabIds.count < SplitGroup.maximumTabs,
              let flatAxis = SplitDropLayoutEligibility.flatAxis(
                  in: context.group.layoutTree,
                  childCount: 2
              ),
              let hit = context.leafHit,
              SplitDropTargetGeometry.isNearInternalDivider(
                  location: context.location,
                  leafRect: hit.rect,
                  bounds: context.bounds,
                  rootAxis: flatAxis
              ) == false
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(
            at: context.location,
            in: hit.rect,
            mode: .create
        ) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != flatAxis
            else {
                continue
            }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .plane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .planeEdge
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedTabId: context.previewTabId
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }
        return nil
    }

    static func rootOrPlaneTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        if context.draggedTabIsInGroup == false,
           let rootSide = SplitDropCaptureHitPolicy.side(
               at: context.location,
               in: context.bounds,
               mode: .create
           ) {
            let target = SplitDropTarget(
                tabId: SplitLayoutGeometry.edgeTabId(
                    in: context.group.layoutTree,
                    for: rootSide,
                    in: context.bounds
                ) ?? context.group.tabIds.first ?? context.previewTabId,
                side: rootSide,
                targetRect: context.bounds,
                scope: .group,
                previewStyle: .edge,
                planePath: [],
                intent: .rootEdge
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedTabId: context.previewTabId
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }

        for plane in SplitDropTargetGeometry.planesContainingLocation(
            in: context.group.layoutTree,
            location: context.location,
            bounds: context.bounds
        ) {
            for side in SplitDropCaptureHitPolicy.sides(
                at: context.location,
                in: plane.rect,
                mode: .create
            ) {
                guard let node = context.group.layoutTree.node(at: plane.path),
                      let targetTabId = SplitLayoutGeometry.edgeTabId(
                          in: node,
                          for: side,
                          in: plane.rect
                      ) ?? node.tabIds.first
                else {
                    continue
                }
                let target = SplitDropTarget(
                    tabId: targetTabId,
                    side: side,
                    targetRect: plane.rect,
                    scope: plane.path.isEmpty ? .group : .plane,
                    previewStyle: .edge,
                    planePath: plane.path,
                    intent: plane.path.isEmpty ? .rootEdge : .planeEdge
                )
                if let resolved = SplitDropCandidate(
                    target: target,
                    draggedTabId: context.previewTabId
                ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                    return resolved
                }
            }
        }
        return nil
    }

    static func siblingTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let flatAxis = SplitDropLayoutEligibility.flatAxis(
            in: context.group.layoutTree
        ),
        let hit = context.leafHit
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(
            at: context.location,
            in: hit.rect,
            mode: .create
        ) where side.insertionAxis == flatAxis {
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .siblingEdge
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedTabId: context.previewTabId
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }
        return nil
    }

    static func parentSiblingTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedTabId = context.draggedTabId,
              context.draggedTabIsInGroup,
              let hit = context.leafHit,
              hit.tabId != draggedTabId,
              let parentAxis = SplitDropLayoutEligibility.parentAxis(
                  for: hit.path,
                  in: context.group.layoutTree
              )
        else {
            return nil
        }

        let parentPath = Array(hit.path.dropLast())
        for side in SplitDropTargetGeometry.rankedEdgeSides(
            at: context.location,
            in: hit.rect
        ) where side.insertionAxis == parentAxis {
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: parentPath.isEmpty ? .group : .plane,
                previewStyle: .edge,
                planePath: parentPath,
                intent: .siblingEdge
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedTabId: draggedTabId
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }
        return nil
    }
}
