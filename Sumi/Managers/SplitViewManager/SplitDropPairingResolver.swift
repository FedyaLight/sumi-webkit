import Foundation

enum SplitDropPairingResolver {
    static func flatThreeTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedTabId = context.draggedTabId,
              context.group.tabIds.count == 3,
              let flatAxis = SplitDropLayoutEligibility.flatAxis(
                  in: context.group.layoutTree,
                  childCount: 3
              ),
              let hit = context.leafHit,
              hit.tabId != draggedTabId,
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
                intent: .flatThreePair
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

    static func mixedThreeOneTarget(
        in context: SplitDropResolutionContext
    ) -> SplitDropTarget? {
        guard let draggedTabId = context.draggedTabId,
              context.draggedTabIsInGroup,
              context.group.tabIds.count == SplitGroup.maximumTabs,
              let structure = SplitDropLayoutEligibility.mixedThreeOne(
                  in: context.group.layoutTree
              ),
              let hit = context.leafHit,
              hit.tabId != draggedTabId,
              structure.canPair(
                  draggedTabId: draggedTabId,
                  targetTabId: hit.tabId
              )
        else {
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
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .mixedThreeOnePair
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
}
