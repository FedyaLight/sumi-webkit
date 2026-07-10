import Foundation

struct SplitFullGroupLayoutCatalog {
    private struct CacheKey: Hashable {
        let tabIds: Set<UUID>

        init(tabIds: [UUID]) {
            self.tabIds = Set(tabIds)
        }
    }

    private var treesByKey: [CacheKey: [SplitLayoutTree]] = [:]

    mutating func removeAll(keepingCapacity: Bool) {
        treesByKey.removeAll(keepingCapacity: keepingCapacity)
    }

    mutating func trees(for tabIds: [UUID]) -> [SplitLayoutTree] {
        guard tabIds.count == SplitGroup.maximumTabs,
              Set(tabIds).count == tabIds.count
        else {
            return []
        }

        let key = CacheKey(tabIds: tabIds)
        if let cached = treesByKey[key] {
            return cached
        }

        var seen = Set<SplitLayoutTree>()
        var trees: [SplitLayoutTree] = []

        func append(_ tree: SplitLayoutTree) {
            guard let canonical = SplitLayoutReconciler.canonicalizedForTiles(tree),
                  seen.insert(canonical).inserted
            else {
                return
            }
            trees.append(canonical)
        }

        for rootAxis in [SplitAxis.row, .column] {
            forEachPermutation(of: tabIds) { ids in
                let childAxis = perpendicularAxis(to: rootAxis)
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0..<2]), size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[2..<4]), size: 0.5),
                        ]
                    )
                )

                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[0..<3]), size: 0.5),
                            SplitLayoutTree.leaf(tabId: ids[3], size: 0.5),
                        ]
                    )
                )
                append(
                    SplitLayoutTree.split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            SplitLayoutTree.leaf(tabId: ids[0], size: 0.5),
                            equalLeafSplit(axis: childAxis, tabIds: Array(ids[1..<4]), size: 0.5),
                        ]
                    )
                )

                for splitIndex in 0..<3 {
                    var cursor = 0
                    let children: [SplitLayoutTree] = (0..<3).map { index in
                        if index == splitIndex {
                            let split = equalLeafSplit(
                                axis: childAxis,
                                tabIds: Array(ids[cursor..<cursor + 2]),
                                size: 1.0 / 3.0
                            )
                            cursor += 2
                            return split
                        }
                        let leaf = SplitLayoutTree.leaf(
                            tabId: ids[cursor],
                            size: 1.0 / 3.0
                        )
                        cursor += 1
                        return leaf
                    }
                    append(
                        SplitLayoutTree.split(
                            axis: rootAxis,
                            size: 1,
                            children: children
                        )
                    )
                }
            }
        }

        if treesByKey.count >= 32 {
            treesByKey.removeAll(keepingCapacity: true)
        }
        treesByKey[key] = trees
        return trees
    }

    private func equalLeafSplit(
        axis: SplitAxis,
        tabIds: [UUID],
        size: Double
    ) -> SplitLayoutTree {
        let childSize = 1 / Double(max(1, tabIds.count))
        return SplitLayoutTree.split(
            axis: axis,
            size: size,
            children: tabIds.map {
                SplitLayoutTree.leaf(tabId: $0, size: childSize)
            }
        )
    }

    private func forEachPermutation(
        of ids: [UUID],
        _ body: ([UUID]) -> Void
    ) {
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

            for index in startIndex..<values.count {
                values.swapAt(startIndex, index)
                permute(from: startIndex + 1)
                values.swapAt(startIndex, index)
            }
        }
        permute(from: 0)
    }

    private func perpendicularAxis(to axis: SplitAxis) -> SplitAxis {
        axis == .row ? .column : .row
    }
}
