enum SplitFullGroupDropResolver {
    static func panePairTarget(
        in context: SplitDropResolutionContext,
        layouts: inout SplitFullGroupLayoutCatalog
    ) -> SplitDropTarget? {
        guard let draggedTabId = context.draggedTabId,
              context.draggedTabIsInGroup,
              context.group.tabIds.count == SplitGroup.maximumTabs,
              let hit = context.leafHit,
              hit.tabId != draggedTabId
        else {
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
                  ) != insertionAxis
            else {
                continue
            }

            let previewRect = SplitDropTargetGeometry.halfRect(
                for: side,
                in: hit.rect
            )
            guard let resolvedTree = SplitFullGroupPairRanker.bestTree(
                among: layouts.trees(for: context.group.tabIds),
                preserving: context.group.layoutTree,
                draggedTabId: draggedTabId,
                targetTabId: hit.tabId,
                side: side,
                desiredRect: previewRect,
                bounds: context.bounds
            ) else {
                continue
            }

            let target = SplitDropTarget(
                tabId: hit.tabId,
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
                draggedTabId: draggedTabId,
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
        guard let draggedTabId = context.draggedTabId,
              context.draggedTabIsInGroup,
              context.group.tabIds.count == SplitGroup.maximumTabs,
              let flatAxis = SplitDropLayoutEligibility.flatAxis(
                  in: context.group.layoutTree,
                  childCount: SplitGroup.maximumTabs
              ),
              let hit = context.leafHit
        else {
            return nil
        }

        for side in SplitDropTargetGeometry.rankedEdgeSides(
            at: context.location,
            in: hit.rect
        ) {
            guard let insertionAxis = side.insertionAxis else { continue }

            if insertionAxis == flatAxis {
                guard hit.tabId != draggedTabId else { continue }
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: hit.rect,
                    scope: .pane,
                    previewStyle: .edge,
                    planePath: hit.path,
                    intent: .flatFourReorder
                )
                if let resolved = SplitDropCandidate(
                    target: target,
                    draggedTabId: draggedTabId
                ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                    return resolved
                }
                continue
            }

            if hit.tabId == draggedTabId {
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: context.bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                if let resolved = SplitDropCandidate(
                    target: target,
                    draggedTabId: draggedTabId
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
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatFourPair
            )
            if let resolved = SplitDropCandidate(
                target: target,
                draggedTabId: draggedTabId,
                previewRect: previewRect
            ).resolved(in: context.group.layoutTree, bounds: context.bounds) {
                return resolved
            }
        }

        guard hit.tabId != draggedTabId,
              let middleSide = SplitDropTargetGeometry.middleRootSide(
                  for: flatAxis,
                  at: context.location,
                  in: hit.rect
              )
        else {
            return nil
        }

        return SplitDropCandidate(
            target: SplitDropTarget(
                tabId: hit.tabId,
                side: middleSide,
                targetRect: context.bounds,
                scope: .group,
                previewStyle: .edge,
                planePath: [],
                intent: .rootEdge
            ),
            draggedTabId: draggedTabId
        ).resolved(in: context.group.layoutTree, bounds: context.bounds)
    }
}
