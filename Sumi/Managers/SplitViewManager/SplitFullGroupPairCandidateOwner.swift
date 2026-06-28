import CoreGraphics
import Foundation

struct SplitFullGroupPairCandidateOwner {
    private struct CandidateCacheKey: Hashable {
        let tabIds: Set<UUID>

        init(tabIds: [UUID]) {
            self.tabIds = Set(tabIds)
        }
    }

    private struct Candidate {
        let tree: SplitLayoutTree
        let overlapRatio: CGFloat
        let preservedPairCount: Int
        let rootAxisMatches: Bool
        let areaDelta: CGFloat
        let stableMovement: CGFloat

        func isBetter(than other: Candidate?) -> Bool {
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

    private struct PairSignature: Hashable {
        let axis: SplitAxis
        let first: UUID
        let second: UUID
    }

    private var candidateTreesByKey: [CandidateCacheKey: [SplitLayoutTree]] = [:]

    mutating func removeAllCachedCandidates(keepingCapacity: Bool) {
        candidateTreesByKey.removeAll(keepingCapacity: keepingCapacity)
    }

    mutating func bestPairTree(
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
        var bestCandidate: Candidate?

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
            let scoredCandidate = Candidate(
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
        let cacheKey = CandidateCacheKey(tabIds: tabIds)
        if let cached = candidateTreesByKey[cacheKey] {
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
        if candidateTreesByKey.count >= 32 {
            candidateTreesByKey.removeAll(keepingCapacity: true)
        }
        candidateTreesByKey[cacheKey] = result
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

    private func directLeafPairSignatures(in tree: SplitLayoutTree) -> Set<PairSignature> {
        switch tree {
        case .leaf:
            return []
        case .split(let axis, _, let children):
            var result = Set<PairSignature>()
            if children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1] {
                result.insert(PairSignature(axis: axis, first: first, second: second))
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
