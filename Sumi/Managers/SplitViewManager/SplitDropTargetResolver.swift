import CoreGraphics
import Foundation

struct SplitDropTargetResolver {
    private struct FullGroupCandidateCacheKey: Hashable {
        let tabIds: Set<UUID>

        init(tabIds: [UUID]) {
            self.tabIds = Set(tabIds)
        }
    }

    private static let previewPlaceholderTabId = UUID()

    private var fullGroupCandidateTreesByKey: [FullGroupCandidateCacheKey: [SplitLayoutTree]] = [:]

    mutating func removeAllCachedCandidates(keepingCapacity: Bool) {
        fullGroupCandidateTreesByKey.removeAll(keepingCapacity: keepingCapacity)
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
            guard let resolvedTree = bestFullGroupPairTree(
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

    private struct FullGroupPairCandidate {
        let tree: SplitLayoutTree
        let overlapRatio: CGFloat
        let preservedPairCount: Int
        let rootAxisMatches: Bool
        let areaDelta: CGFloat
        let stableMovement: CGFloat

        func isBetter(than other: FullGroupPairCandidate?) -> Bool {
            guard let other else { return true }
            if abs(overlapRatio - other.overlapRatio) > 0.0001 {
                return overlapRatio > other.overlapRatio
            }
            if preservedPairCount != other.preservedPairCount {
                return preservedPairCount > other.preservedPairCount
            }
            if rootAxisMatches != other.rootAxisMatches {
                return rootAxisMatches
            }
            if abs(areaDelta - other.areaDelta) > 0.0001 {
                return areaDelta < other.areaDelta
            }
            return stableMovement < other.stableMovement
        }
    }

    private struct SplitPairSignature: Hashable {
        let axis: SplitAxis
        let first: UUID
        let second: UUID
    }

    private mutating func bestFullGroupPairTree(
        in tree: SplitLayoutTree,
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide,
        desiredRect: CGRect,
        bounds: CGRect
    ) -> SplitLayoutTree? {
        guard let pairAxis = side.insertionAxis,
              tree.tabIds.count == SplitGroup.maximumTabs,
              tree.contains(draggedTabId),
              tree.contains(targetTabId),
              draggedTabId != targetTabId
        else {
            return nil
        }

        let orderedPair = pairOrder(
            draggedTabId: draggedTabId,
            targetTabId: targetTabId,
            side: side
        )
        let originalRootAxis = rootAxis(of: tree)
        let currentRects = tree.leafRects(in: bounds)
        let preservedPairs = directLeafPairSignatures(in: tree)
            .filter { $0.first != draggedTabId && $0.second != draggedTabId }
        var bestCandidate: FullGroupPairCandidate?

        for candidate in fullGroupCandidateTrees(tabIds: tree.tabIds) {
            guard candidate.hasDirectedLeafPair(
                axis: pairAxis,
                first: orderedPair.first,
                second: orderedPair.second
            ) else {
                continue
            }
            let candidateRects = candidate.leafRects(in: bounds)
            guard candidate.hasSameStructure(as: tree) == false,
                  let draggedRect = candidateRects[draggedTabId]
            else {
                continue
            }
            let overlapRatio = intersectionArea(draggedRect, desiredRect)
                / max(1, area(of: desiredRect))
            guard overlapRatio > 0 else { continue }
            let candidatePairs = directLeafPairSignatures(in: candidate)
            let preservedPairCount = preservedPairs.filter { candidatePairs.contains($0) }.count
            let areaDelta = abs(area(of: draggedRect) - area(of: desiredRect))
                / max(1, area(of: bounds))
            let stableMovement = stableLeafMovement(
                from: currentRects,
                to: candidateRects,
                excluding: draggedTabId
            )
            let scoredCandidate = FullGroupPairCandidate(
                tree: candidate,
                overlapRatio: overlapRatio,
                preservedPairCount: preservedPairCount,
                rootAxisMatches: rootAxis(of: candidate) == originalRootAxis,
                areaDelta: areaDelta,
                stableMovement: stableMovement
            )
            if scoredCandidate.isBetter(than: bestCandidate) {
                bestCandidate = scoredCandidate
            }
        }

        return bestCandidate?.tree
    }

    private mutating func fullGroupCandidateTrees(tabIds: [UUID]) -> [SplitLayoutTree] {
        guard tabIds.count == SplitGroup.maximumTabs,
              Set(tabIds).count == tabIds.count
        else { return [] }
        let cacheKey = FullGroupCandidateCacheKey(tabIds: tabIds)
        if let cached = fullGroupCandidateTreesByKey[cacheKey] {
            return cached
        }

        var seen = Set<SplitLayoutTree>()
        var result: [SplitLayoutTree] = []

        func append(_ tree: SplitLayoutTree) {
            guard let canonical = tree.canonicalizedForTiles(),
                  seen.insert(canonical).inserted
            else {
                return
            }
            result.append(canonical)
        }

        for rootAxis in [SplitAxis.row, .column] {
            forEachPermutation(of: tabIds) { ids in
                let childAxis = perpendicularAxis(to: rootAxis)
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0 ..< 2]), size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[2 ..< 4]), size: 0.5)
                        ]
                    )
                )

                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0 ..< 3]), size: 0.5),
                            SplitLayoutTree.leaf(tabId: ids[3], size: 0.5)
                        ]
                    )
                )
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            SplitLayoutTree.leaf(tabId: ids[0], size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[1 ..< 4]), size: 0.5)
                        ]
                    )
                )

                for splitIndex in 0 ..< 3 {
                    var cursor = 0
                    let children: [SplitLayoutTree] = (0 ..< 3).map { index in
                        if index == splitIndex {
                            let split = equalLeafSplit(
                                axis: childAxis,
                                tabIds: Array(ids[cursor ..< cursor + 2]),
                                size: 1.0 / 3.0
                            )
                            cursor += 2
                            return split
                        }
                        let leaf = SplitLayoutTree.leaf(tabId: ids[cursor], size: 1.0 / 3.0)
                        cursor += 1
                        return leaf
                    }
                    append(SplitLayoutTree.split(axis: rootAxis, size: 1, children: children))
                }
            }
        }
        if fullGroupCandidateTreesByKey.count >= 32 {
            fullGroupCandidateTreesByKey.removeAll(keepingCapacity: true)
        }
        fullGroupCandidateTreesByKey[cacheKey] = result
        return result
    }

    private func equalLeafSplit(axis: SplitAxis, tabIds: [UUID], size: Double) -> SplitLayoutTree {
        let childSize = 1 / Double(max(1, tabIds.count))
        return SplitLayoutTree.split(
            axis: axis,
            size: size,
            children: tabIds.map { SplitLayoutTree.leaf(tabId: $0, size: childSize) }
        )
    }

    private func forEachPermutation(of ids: [UUID], _ body: ([UUID]) -> Void) {
        guard ids.isEmpty == false else {
            body([])
            return
        }

        var values = ids
        func permute(from startIndex: Int) {
            if startIndex == values.count {
                body(values)
                return
            }

            for index in startIndex ..< values.count {
                values.swapAt(startIndex, index)
                permute(from: startIndex + 1)
                values.swapAt(startIndex, index)
            }
        }
        permute(from: 0)
    }

    private func pairOrder(
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> (first: UUID, second: UUID) {
        if side == .left || side == .top {
            return (draggedTabId, targetTabId)
        }
        return (targetTabId, draggedTabId)
    }

    private func perpendicularAxis(to axis: SplitAxis) -> SplitAxis {
        axis == .row ? .column : .row
    }

    private func rootAxis(of tree: SplitLayoutTree) -> SplitAxis? {
        if case .split(let axis, _, _) = tree {
            return axis
        }
        return nil
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

    private func directLeafPairSignatures(in tree: SplitLayoutTree) -> Set<SplitPairSignature> {
        switch tree {
        case .leaf:
            return []
        case .split(let axis, _, let children):
            var result = Set<SplitPairSignature>()
            if children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1] {
                result.insert(SplitPairSignature(axis: axis, first: first, second: second))
            }
            for child in children {
                result.formUnion(directLeafPairSignatures(in: child))
            }
            return result
        }
    }

    private func stableLeafMovement(
        from currentRects: [UUID: CGRect],
        to candidateRects: [UUID: CGRect],
        excluding draggedTabId: UUID
    ) -> CGFloat {
        currentRects.reduce(CGFloat(0)) { partial, element in
            let (tabId, currentRect) = element
            guard tabId != draggedTabId,
                  let candidateRect = candidateRects[tabId]
            else {
                return partial
            }
            return partial + hypot(
                currentRect.midX - candidateRect.midX,
                currentRect.midY - candidateRect.midY
            )
        }
    }

    private func area(of rect: CGRect) -> CGFloat {
        guard rect.isNull == false,
              rect.isInfinite == false
        else {
            return 0
        }
        return max(0, rect.width) * max(0, rect.height)
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        area(of: lhs.intersection(rhs))
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

private extension SplitLayoutTree {
    func hasDirectedLeafPair(axis expectedAxis: SplitAxis, first expectedFirst: UUID, second expectedSecond: UUID) -> Bool {
        switch self {
        case .leaf:
            return false
        case .split(let axis, _, let children):
            if axis == expectedAxis,
               children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1],
               first == expectedFirst,
               second == expectedSecond {
                return true
            }
            return children.contains {
                $0.hasDirectedLeafPair(
                    axis: expectedAxis,
                    first: expectedFirst,
                    second: expectedSecond
                )
            }
        }
    }
}
