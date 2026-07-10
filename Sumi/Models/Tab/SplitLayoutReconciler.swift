import Foundation

/// Repairs persisted or incrementally-mutated trees into the finite set of
/// layouts supported by the tiled UI. It never interprets pointer geometry or
/// drag intent.
enum SplitLayoutReconciler {
    static func canonicalizedForTiles(_ tree: SplitLayoutTree) -> SplitLayoutTree? {
        let ids = tree.tabIds
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(ids)
        guard uniqueIds.count >= SplitGroup.minimumTabs,
              uniqueIds.count <= SplitGroup.maximumTabs,
              uniqueIds.count == ids.count
        else {
            return nil
        }

        if let canonical = canonicalTreePreservingSizes(tree) {
            return SplitLayoutSizing.normalizingSiblingSizes(in: canonical)
        }

        let fallbackAxis: SplitAxis
        if case .split(let axis, _, _) = tree {
            fallbackAxis = axis
        } else {
            fallbackAxis = .row
        }
        return SplitLayoutFactory.equalSplit(axis: fallbackAxis, tabIds: uniqueIds)
    }

    static func canonicalTreePreservingSizes(_ tree: SplitLayoutTree) -> SplitLayoutTree? {
        let ids = tree.tabIds
        guard ids.count >= SplitGroup.minimumTabs,
              ids.count <= SplitGroup.maximumTabs,
              Set(ids).count == ids.count
        else {
            return nil
        }

        switch tree {
        case .leaf:
            return nil
        case .split(let axis, let size, let children):
            guard children.count >= 2,
                  children.count <= SplitGroup.maximumTabs
            else {
                return nil
            }

            if let flattened = flatteningSameAxisChildren(
                axis: axis,
                size: size,
                children: children
            ) {
                return canonicalTreePreservingSizes(flattened)
            }

            if children.allSatisfy(isLeaf) {
                return SplitLayoutSizing.normalizingSiblingSizes(
                    in: .split(axis: axis, size: size, children: children)
                )
            }

            if let mixedFlatPair = normalizedMixedFlatPair(
                tree: tree,
                axis: axis,
                size: size,
                children: children
            ) {
                return mixedFlatPair
            }

            guard children.count == 2 else { return nil }
            let normalizedChildren = children.compactMap { child -> SplitLayoutTree? in
                switch child {
                case .leaf:
                    return child
                case .split(let childAxis, let childSize, let grandchildren):
                    guard grandchildren.count >= 2,
                          grandchildren.count <= 3,
                          grandchildren.allSatisfy(isLeaf)
                    else {
                        return nil
                    }
                    return SplitLayoutSizing.normalizingSiblingSizes(
                        in: .split(
                            axis: childAxis,
                            size: childSize,
                            children: grandchildren
                        )
                    )
                }
            }
            guard normalizedChildren.count == children.count else { return nil }
            return SplitLayoutSizing.normalizingSiblingSizes(
                in: .split(
                    axis: axis,
                    size: size,
                    children: normalizedChildren
                )
            )
        }
    }

    private static func normalizedMixedFlatPair(
        tree: SplitLayoutTree,
        axis: SplitAxis,
        size: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        guard children.count == 3,
              tree.tabIds.count == SplitGroup.maximumTabs
        else {
            return nil
        }

        let splitIndices = children.indices.filter { index in
            if case .split(let childAxis, _, let grandchildren) = children[index] {
                return childAxis != axis
                    && grandchildren.count == 2
                    && grandchildren.allSatisfy(isLeaf)
            }
            return false
        }
        guard splitIndices.count == 1 else { return nil }

        let normalizedChildren = children.enumerated().map { index, child in
            index == splitIndices[0]
                ? SplitLayoutSizing.normalizingSiblingSizes(in: child)
                : child
        }
        return SplitLayoutSizing.normalizingSiblingSizes(
            in: .split(axis: axis, size: size, children: normalizedChildren)
        )
    }

    private static func flatteningSameAxisChildren(
        axis: SplitAxis,
        size: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        var didFlatten = false
        let parentWeights = SplitLayoutSizing.normalizedWeights(
            children.map(\.sizeInParent)
        )
        let flattened = zip(children, parentWeights).flatMap { child, parentWeight in
            guard case .split(let childAxis, _, let grandchildren) = child,
                  childAxis == axis
            else {
                return [SplitLayoutSizing.settingSize(parentWeight, in: child)]
            }
            didFlatten = true
            let childWeights = SplitLayoutSizing.normalizedWeights(
                grandchildren.map(\.sizeInParent)
            )
            return zip(grandchildren, childWeights).map { grandchild, childWeight in
                SplitLayoutSizing.settingSize(
                    parentWeight * childWeight,
                    in: grandchild
                )
            }
        }
        guard didFlatten,
              flattened.count >= 2,
              flattened.count <= SplitGroup.maximumTabs
        else {
            return nil
        }
        return .split(axis: axis, size: size, children: flattened)
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
