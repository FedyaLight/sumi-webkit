import CoreGraphics
import Foundation

enum SplitFullGroupPairRanker {
    private struct Score {
        let tree: SplitLayoutTree
        let overlapRatio: CGFloat
        let preservedPairCount: Int
        let rootAxisMatches: Bool
        let areaDelta: CGFloat
        let stableMovement: CGFloat

        func isBetter(than other: Score?) -> Bool {
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

    static func bestTree(
        among candidates: [SplitLayoutTree],
        preserving tree: SplitLayoutTree,
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
        let currentRects = SplitLayoutGeometry.leafRects(in: tree, rect: bounds)
        let preservedPairs = directLeafPairSignatures(in: tree)
            .filter { $0.first != draggedTabId && $0.second != draggedTabId }
        var bestScore: Score?

        for candidate in candidates {
            guard hasDirectedLeafPair(
                in: candidate,
                axis: pairAxis,
                first: orderedPair.first,
                second: orderedPair.second
            ) else {
                continue
            }

            let candidateRects = SplitLayoutGeometry.leafRects(
                in: candidate,
                rect: bounds
            )
            guard candidate.hasSameStructure(as: tree) == false,
                  let draggedRect = candidateRects[draggedTabId]
            else {
                continue
            }

            let overlapRatio = intersectionArea(draggedRect, desiredRect)
                / max(1, area(of: desiredRect))
            guard overlapRatio > 0 else { continue }

            let candidatePairs = directLeafPairSignatures(in: candidate)
            let score = Score(
                tree: candidate,
                overlapRatio: overlapRatio,
                preservedPairCount: preservedPairs.filter {
                    candidatePairs.contains($0)
                }.count,
                rootAxisMatches: rootAxis(of: candidate) == originalRootAxis,
                areaDelta: abs(area(of: draggedRect) - area(of: desiredRect))
                    / max(1, area(of: bounds)),
                stableMovement: stableLeafMovement(
                    from: currentRects,
                    to: candidateRects,
                    excluding: draggedTabId
                )
            )
            if score.isBetter(than: bestScore) {
                bestScore = score
            }
        }

        return bestScore?.tree
    }

    private static func pairOrder(
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> (first: UUID, second: UUID) {
        if side == .left || side == .top {
            return (draggedTabId, targetTabId)
        }
        return (targetTabId, draggedTabId)
    }

    private static func rootAxis(of tree: SplitLayoutTree) -> SplitAxis? {
        if case .split(let axis, _, _) = tree {
            return axis
        }
        return nil
    }

    private static func directLeafPairSignatures(
        in tree: SplitLayoutTree
    ) -> Set<PairSignature> {
        switch tree {
        case .leaf:
            return []
        case .split(let axis, _, let children):
            var result = Set<PairSignature>()
            if children.count == 2,
               case .leaf(let first, _) = children[0],
               case .leaf(let second, _) = children[1] {
                result.insert(
                    PairSignature(axis: axis, first: first, second: second)
                )
            }
            for child in children {
                result.formUnion(directLeafPairSignatures(in: child))
            }
            return result
        }
    }

    private static func stableLeafMovement(
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

    private static func area(of rect: CGRect) -> CGFloat {
        guard rect.isNull == false, rect.isInfinite == false else { return 0 }
        return max(0, rect.width) * max(0, rect.height)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        area(of: lhs.intersection(rhs))
    }

    private static func hasDirectedLeafPair(
        in tree: SplitLayoutTree,
        axis expectedAxis: SplitAxis,
        first expectedFirst: UUID,
        second expectedSecond: UUID
    ) -> Bool {
        switch tree {
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
                hasDirectedLeafPair(
                    in: $0,
                    axis: expectedAxis,
                    first: expectedFirst,
                    second: expectedSecond
                )
            }
        }
    }
}
