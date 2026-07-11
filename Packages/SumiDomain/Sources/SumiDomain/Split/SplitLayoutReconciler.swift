import Foundation

/// Repairs decoded or incrementally-mutated trees into the finite topology
/// set supported by the tiled browser UI.
public enum SplitLayoutReconciler {
    public static func canonicalizedForTiles(
        _ tree: SplitLayoutTree
    ) -> SplitLayoutTree? {
        let memberIDs = tree.memberIDs
        guard memberIDs.count >= SplitGroup.minimumMembers,
              memberIDs.count <= SplitGroup.maximumMembers,
              Set(memberIDs).count == memberIDs.count else {
            return nil
        }

        if let canonical = canonicalTreePreservingWeights(tree) {
            return SplitLayoutSizing.normalizingSiblingWeights(in: canonical)
        }

        let fallbackAxis: SplitAxis
        if case .split(let axis, _, _) = tree {
            fallbackAxis = axis
        } else {
            fallbackAxis = .row
        }
        return SplitLayoutFactory.equalSplit(
            axis: fallbackAxis,
            members: tree.members
        )
    }

    public static func canonicalTreePreservingWeights(
        _ tree: SplitLayoutTree
    ) -> SplitLayoutTree? {
        let memberIDs = tree.memberIDs
        guard memberIDs.count >= SplitGroup.minimumMembers,
              memberIDs.count <= SplitGroup.maximumMembers,
              Set(memberIDs).count == memberIDs.count else {
            return nil
        }

        switch tree {
        case .leaf:
            return nil
        case .split(let axis, let weight, let children):
            guard children.count >= 2,
                  children.count <= SplitGroup.maximumMembers else {
                return nil
            }

            if let flattened = flatteningSameAxisChildren(
                axis: axis,
                weight: weight,
                children: children
            ) {
                return canonicalTreePreservingWeights(flattened)
            }

            if children.allSatisfy(isLeaf) {
                return SplitLayoutSizing.normalizingSiblingWeights(
                    in: .split(axis: axis, weight: weight, children: children)
                )
            }

            if let mixedFlatPair = normalizedMixedFlatPair(
                tree: tree,
                axis: axis,
                weight: weight,
                children: children
            ) {
                return mixedFlatPair
            }

            guard children.count == 2 else { return nil }
            let normalizedChildren = children.compactMap {
                child -> SplitLayoutTree? in
                switch child {
                case .leaf:
                    return child
                case .split(let childAxis, let childWeight, let grandchildren):
                    guard grandchildren.count >= 2,
                          grandchildren.count <= 3,
                          grandchildren.allSatisfy(isLeaf) else {
                        return nil
                    }
                    return SplitLayoutSizing.normalizingSiblingWeights(
                        in: .split(
                            axis: childAxis,
                            weight: childWeight,
                            children: grandchildren
                        )
                    )
                }
            }
            guard normalizedChildren.count == children.count else { return nil }
            return SplitLayoutSizing.normalizingSiblingWeights(
                in: .split(
                    axis: axis,
                    weight: weight,
                    children: normalizedChildren
                )
            )
        }
    }

    private static func normalizedMixedFlatPair(
        tree: SplitLayoutTree,
        axis: SplitAxis,
        weight: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        guard children.count == 3,
              tree.leafCount == SplitGroup.maximumMembers else {
            return nil
        }

        let splitIndices = children.indices.filter { index in
            if case .split(
                let childAxis,
                _,
                let grandchildren
            ) = children[index] {
                return childAxis != axis
                    && grandchildren.count == 2
                    && grandchildren.allSatisfy(isLeaf)
            }
            return false
        }
        guard splitIndices.count == 1 else { return nil }

        let normalizedChildren = children.enumerated().map { index, child in
            index == splitIndices[0]
                ? SplitLayoutSizing.normalizingSiblingWeights(in: child)
                : child
        }
        return SplitLayoutSizing.normalizingSiblingWeights(
            in: .split(
                axis: axis,
                weight: weight,
                children: normalizedChildren
            )
        )
    }

    private static func flatteningSameAxisChildren(
        axis: SplitAxis,
        weight: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        var didFlatten = false
        let parentWeights = SplitLayoutSizing.normalizedWeights(
            children.map(\.weightInParent)
        )
        let flattened = zip(children, parentWeights).flatMap {
            child,
            parentWeight -> [SplitLayoutTree] in
            guard case .split(
                let childAxis,
                _,
                let grandchildren
            ) = child,
                childAxis == axis else {
                return [
                    SplitLayoutSizing.settingWeight(parentWeight, in: child),
                ]
            }
            didFlatten = true
            let childWeights = SplitLayoutSizing.normalizedWeights(
                grandchildren.map(\.weightInParent)
            )
            return zip(grandchildren, childWeights).map {
                grandchild,
                childWeight in
                SplitLayoutSizing.settingWeight(
                    parentWeight * childWeight,
                    in: grandchild
                )
            }
        }
        guard didFlatten,
              flattened.count >= 2,
              flattened.count <= SplitGroup.maximumMembers else {
            return nil
        }
        return .split(axis: axis, weight: weight, children: flattened)
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
