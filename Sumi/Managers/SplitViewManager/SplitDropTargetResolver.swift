import CoreGraphics
import Foundation

struct SplitDropTargetResolver {
    private static let previewPlaceholderTabId = UUID()

    private var fullGroupPairCandidateOwner = SplitFullGroupPairCandidateOwner()

    mutating func removeAllCachedCandidates(keepingCapacity: Bool) {
        fullGroupPairCandidateOwner.removeAllCachedCandidates(keepingCapacity: keepingCapacity)
    }

    mutating func target(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let canonicalGroup = group.canonicalizedForTiles() else { return nil }
        let previewTabId = draggedTabId ?? Self.previewPlaceholderTabId
        let draggedTabIsInGroup = draggedTabId.map { canonicalGroup.contains($0) } ?? false
        let canInsertEdge = draggedTabIsInGroup || canonicalGroup.tabIds.count < SplitGroup.maximumTabs

        if draggedTabIsInGroup,
           canonicalGroup.tabIds.count == SplitGroup.maximumTabs,
           let flatFourTarget = resolvedFullFlatFourTarget(
               in: canonicalGroup,
               at: location,
               bounds: bounds,
               draggedTabId: draggedTabId
           ) {
            return flatFourTarget
        }

        if draggedTabIsInGroup,
           canonicalGroup.tabIds.count == SplitGroup.maximumTabs,
           canonicalGroup.layoutTree.isFlatFourLeafLine {
            return nil
        }

        if canInsertEdge {
            if let flatThreePairTarget = resolvedFlatThreePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return flatThreePairTarget
            }

            if let leafLocalTarget = resolvedLeafLocalOrthogonalTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                previewTabId: previewTabId
            ) {
                return leafLocalTarget
            }

            if let pairTarget = resolvedFlatFourPairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return pairTarget
            }

            if let mixedPairTarget = resolvedMixedThreeOnePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return mixedPairTarget
            }

            if let parentSiblingTarget = resolvedParentSiblingEdgeTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return parentSiblingTarget
            }

            if let fullGroupPairTarget = resolvedFullGroupPanePairTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                draggedTabId: draggedTabId
            ) {
                return fullGroupPairTarget
            }

            if draggedTabIsInGroup == false,
               let rootSide = SplitDropCaptureHitPolicy.side(at: location, in: bounds, mode: .create) {
                let target = SplitDropTarget(
                    tabId: canonicalGroup.layoutTree.edgeTabId(for: rootSide, in: bounds)
                        ?? canonicalGroup.tabIds.first
                        ?? previewTabId,
                    side: rootSide,
                    targetRect: bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                if let resolved = canonicalGroup.resolvingDrop(
                    draggedTabId: previewTabId,
                    target: target,
                    bounds: bounds
                ) {
                    return resolved.target
                }
            }

            let planes = canonicalGroup.layoutTree.tilePlanes(in: bounds)
                .filter { $0.rect.contains(location) }
                .sorted { lhs, rhs in
                    if lhs.path.count != rhs.path.count {
                        return lhs.path.count > rhs.path.count
                    }
                    return lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
                }

            for plane in planes {
                for side in SplitDropCaptureHitPolicy.sides(at: location, in: plane.rect, mode: .create) {
                    guard let node = canonicalGroup.layoutTree.node(at: plane.path),
                          let targetTabId = node.edgeTabId(for: side, in: plane.rect) ?? node.tabIds.first
                    else {
                        continue
                    }
                    let scope: SplitDropTargetScope = plane.path.isEmpty ? .group : .plane
                    let target = SplitDropTarget(
                        tabId: targetTabId,
                        side: side,
                        targetRect: plane.rect,
                        scope: scope,
                        previewStyle: .edge,
                        planePath: plane.path,
                        intent: plane.path.isEmpty ? .rootEdge : .planeEdge
                    )
                    guard let resolved = canonicalGroup.resolvingDrop(
                        draggedTabId: previewTabId,
                        target: target,
                        bounds: bounds
                    ) else {
                        continue
                    }
                    return resolved.target
                }
            }

            if let siblingTarget = resolvedSiblingEdgeTarget(
                in: canonicalGroup,
                at: location,
                bounds: bounds,
                previewTabId: previewTabId
            ) {
                return siblingTarget
            }
        }

        guard draggedTabIsInGroup == false,
              let hit = canonicalGroup.layoutTree.leafHit(at: location, in: bounds),
              SplitDropCaptureHitPolicy.side(at: location, in: hit.rect, mode: .rearrange) == .center
        else {
            return nil
        }

        let target = SplitDropTarget(
            tabId: hit.tabId,
            side: .center,
            targetRect: hit.rect,
            scope: .pane,
            previewStyle: .center,
            planePath: hit.path,
            intent: .paneCenter
        )
        return canonicalGroup.resolvingDrop(
            draggedTabId: previewTabId,
            target: target,
            bounds: bounds
        )?.target
    }

    func firstSplitTarget(
        currentTabId: UUID,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let side = SplitDropCaptureHitPolicy.side(
            at: location,
            in: bounds,
            mode: .create
        ) else {
            return nil
        }
        return SplitDropTarget(
            tabId: currentTabId,
            side: side,
            targetRect: previewRectForFirstSplit(
                currentTabId: currentTabId,
                previewTabId: draggedTabId ?? UUID(),
                side: side,
                in: bounds
            ) ?? bounds,
            intent: .firstSplit
        )
    }

    private func resolvedLeafLocalOrthogonalTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        previewTabId: UUID
    ) -> SplitDropTarget? {
        guard group.tabIds.count < SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.count == 2,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }
        guard isNearInternalDivider(
            location: location,
            leafRect: hit.rect,
            bounds: bounds,
            rootAxis: rootAxis
        ) == false else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != rootAxis
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
            guard let resolved = group.resolvingDrop(
                draggedTabId: previewTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func isNearInternalDivider(
        location: CGPoint,
        leafRect: CGRect,
        bounds: CGRect,
        rootAxis: SplitAxis
    ) -> Bool {
        let threshold: CGFloat = 24
        switch rootAxis {
        case .row:
            let internalEdge: CGFloat?
            if leafRect.minX > bounds.minX {
                internalEdge = leafRect.minX
            } else if leafRect.maxX < bounds.maxX {
                internalEdge = leafRect.maxX
            } else {
                internalEdge = nil
            }
            guard let internalEdge else { return false }
            return abs(location.x - internalEdge) <= threshold
        case .column:
            let internalEdge: CGFloat?
            if leafRect.minY > bounds.minY {
                internalEdge = leafRect.minY
            } else if leafRect.maxY < bounds.maxY {
                internalEdge = leafRect.maxY
            } else {
                internalEdge = nil
            }
            guard let internalEdge else { return false }
            return abs(location.y - internalEdge) <= threshold
        }
    }

    private func resolvedSiblingEdgeTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        previewTabId: UUID
    ) -> SplitDropTarget? {
        guard case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard side.insertionAxis == rootAxis else { continue }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .siblingEdge
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: previewTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func resolvedFlatThreePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.tabIds.count == 3,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }
        guard isNearInternalDivider(
            location: location,
            leafRect: hit.rect,
            bounds: bounds,
            rootAxis: rootAxis
        ) == false else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard let insertionAxis = side.insertionAxis,
                  insertionAxis != rootAxis
            else {
                continue
            }
            let localPreviewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: localPreviewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatThreePair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: localPreviewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private func resolvedFlatFourPairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        let sides = SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create)
        guard sides.first?.insertionAxis != rootAxis else { return nil }
        for side in sides {
            guard side.insertionAxis != rootAxis else { continue }
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatFourPair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private func resolvedMixedThreeOnePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(_, _, let children) = group.layoutTree,
              children.count == 2,
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        var splitTabIds: [UUID] = []
        var singletonTabId: UUID?
        for child in children {
            switch child {
            case .leaf(let id, _):
                singletonTabId = id
            case .split(_, _, let grandchildren):
                let leafIds = grandchildren.compactMap { grandchild -> UUID? in
                    if case .leaf(let id, _) = grandchild {
                        return id
                    }
                    return nil
                }
                if leafIds.count == 3 {
                    splitTabIds = leafIds
                }
            }
        }

        guard splitTabIds.isEmpty == false,
              let singletonTabId,
              (draggedTabId == singletonTabId && splitTabIds.contains(hit.tabId))
                || (hit.tabId == singletonTabId && splitTabIds.contains(draggedTabId))
        else {
            return nil
        }

        for side in SplitDropCaptureHitPolicy.sides(at: location, in: hit.rect, mode: .create) {
            guard side.insertionAxis != nil else { continue }
            let previewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .mixedThreeOnePair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private func resolvedParentSiblingEdgeTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId,
              let parentAxis = parentAxis(for: hit.path, in: group.layoutTree)
        else {
            return nil
        }

        let parentPath = Array(hit.path.dropLast())
        for side in flatFourEdgeCandidates(at: location, in: hit.rect).map(\.side) {
            guard side.insertionAxis == parentAxis else { continue }
            let scope: SplitDropTargetScope = parentPath.isEmpty ? .group : .plane
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: hit.rect,
                scope: scope,
                previewStyle: .edge,
                planePath: parentPath,
                intent: .siblingEdge
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return resolved.target
        }
        return nil
    }

    private mutating func resolvedFullGroupPanePairTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              let hit = group.layoutTree.leafHit(at: location, in: bounds),
              hit.tabId != draggedTabId
        else {
            return nil
        }

        let candidates = flatFourEdgeCandidates(at: location, in: hit.rect)
        for side in candidates.map(\.side) {
            guard let insertionAxis = side.insertionAxis else { continue }
            if parentAxis(for: hit.path, in: group.layoutTree) == insertionAxis {
                continue
            }

            let previewRect = localHalfRect(for: side, in: hit.rect)
            guard let resolvedTree = fullGroupPairCandidateOwner.bestPairTree(
                in: group.layoutTree,
                draggedTabId: draggedTabId,
                targetTabId: hit.tabId,
                side: side,
                desiredRect: previewRect,
                bounds: bounds
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
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }
        return nil
    }

    private mutating func resolvedFullFlatFourTarget(
        in group: SplitGroup,
        at location: CGPoint,
        bounds: CGRect,
        draggedTabId: UUID?
    ) -> SplitDropTarget? {
        guard let draggedTabId,
              group.contains(draggedTabId),
              group.tabIds.count == SplitGroup.maximumTabs,
              case .split(let rootAxis, _, let children) = group.layoutTree,
              children.allSatisfy({ child in
                  if case .leaf = child { return true }
                  return false
              }),
              let hit = group.layoutTree.leafHit(at: location, in: bounds)
        else {
            return nil
        }

        let candidates = flatFourEdgeCandidates(at: location, in: hit.rect)
        for side in candidates.map(\.side) {
            guard let insertionAxis = side.insertionAxis else { continue }
            if insertionAxis == rootAxis {
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
                guard let resolved = group.resolvingDrop(
                    draggedTabId: draggedTabId,
                    target: target,
                    bounds: bounds
                ) else {
                    continue
                }
                return resolved.target
            }

            if hit.tabId == draggedTabId {
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: bounds,
                    scope: .group,
                    previewStyle: .edge,
                    planePath: [],
                    intent: .rootEdge
                )
                guard let resolved = group.resolvingDrop(
                    draggedTabId: draggedTabId,
                    target: target,
                    bounds: bounds
                ) else {
                    continue
                }
                return resolved.target
            }

            let previewRect = localHalfRect(for: side, in: hit.rect)
            let target = SplitDropTarget(
                tabId: hit.tabId,
                side: side,
                targetRect: previewRect,
                scope: .pane,
                previewStyle: .edge,
                planePath: hit.path,
                intent: .flatFourPair
            )
            guard let resolved = group.resolvingDrop(
                draggedTabId: draggedTabId,
                target: target,
                bounds: bounds
            ) else {
                continue
            }
            return SplitDropTarget(
                tabId: resolved.target.tabId,
                side: resolved.target.side,
                targetRect: previewRect,
                scope: resolved.target.scope,
                previewStyle: resolved.target.previewStyle,
                planePath: resolved.target.planePath,
                intent: resolved.target.intent,
                resolvedLayoutTree: resolved.layoutTree
            )
        }

        guard hit.tabId != draggedTabId,
              let middleSide = fullFlatFourMiddleRootSide(
                for: rootAxis,
                at: location,
                in: hit.rect
              )
        else {
            return nil
        }

        let target = SplitDropTarget(
            tabId: hit.tabId,
            side: middleSide,
            targetRect: bounds,
            scope: .group,
            previewStyle: .edge,
            planePath: [],
            intent: .rootEdge
        )
        return group.resolvingDrop(
            draggedTabId: draggedTabId,
            target: target,
            bounds: bounds
        )?.target
    }

    private func parentAxis(for path: [Int], in tree: SplitLayoutTree) -> SplitAxis? {
        guard path.isEmpty == false else { return nil }
        var node = tree
        for index in path.dropLast() {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index)
            else {
                return nil
            }
            node = children[index]
        }
        if case .split(let axis, _, _) = node {
            return axis
        }
        return nil
    }

    private func fullFlatFourMiddleRootSide(
        for rootAxis: SplitAxis,
        at location: CGPoint,
        in rect: CGRect
    ) -> SplitDropSide? {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return nil }
        let lowerBound: CGFloat = 1.0 / 3.0
        let upperBound: CGFloat = 2.0 / 3.0
        switch rootAxis {
        case .row:
            let normalizedY = (location.y - rect.minY) / rect.height
            guard normalizedY > lowerBound, normalizedY < upperBound else { return nil }
            return location.y >= rect.midY ? .top : .bottom
        case .column:
            let normalizedX = (location.x - rect.minX) / rect.width
            guard normalizedX > lowerBound, normalizedX < upperBound else { return nil }
            return location.x >= rect.midX ? .right : .left
        }
    }

    private func flatFourEdgeCandidates(
        at location: CGPoint,
        in rect: CGRect
    ) -> [(side: SplitDropSide, distance: CGFloat)] {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return [] }
        let threshold: CGFloat = 1.0 / 3.0
        let candidates: [(SplitDropSide, CGFloat, CGFloat)] = [
            (.left, location.x - rect.minX, rect.width),
            (.right, rect.maxX - location.x, rect.width),
            (.top, rect.maxY - location.y, rect.height),
            (.bottom, location.y - rect.minY, rect.height)
        ]
        return candidates
            .compactMap { side, distance, length -> (side: SplitDropSide, distance: CGFloat)? in
                guard length > 0 else { return nil }
                let normalized = distance / length
                guard normalized <= threshold else { return nil }
                return (side, normalized)
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.side.rawValue < rhs.side.rawValue
                }
                return lhs.distance < rhs.distance
            }
    }

    private func localHalfRect(for side: SplitDropSide, in rect: CGRect) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right:
            return CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top:
            return CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .center:
            return rect
        }
    }

    private func previewRectForFirstSplit(
        currentTabId: UUID,
        previewTabId: UUID,
        side: SplitDropSide,
        in bounds: CGRect
    ) -> CGRect? {
        SplitLayoutTree.leaf(tabId: currentTabId, size: 1)
            .insertingAtRoot(tabId: previewTabId, side: side)
            .leafRect(for: previewTabId, in: bounds)
    }
}
