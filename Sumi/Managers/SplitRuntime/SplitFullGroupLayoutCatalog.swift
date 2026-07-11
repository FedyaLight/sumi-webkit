import Foundation
import SumiDomain

struct SplitFullGroupLayoutCatalog {
    private struct CacheKey: Hashable {
        let members: Set<SplitMember>

        init(members: [SplitMember]) {
            self.members = Set(members)
        }
    }

    private var treesByKey: [CacheKey: [SplitLayoutTree]] = [:]

    mutating func removeAll(keepingCapacity: Bool) {
        treesByKey.removeAll(keepingCapacity: keepingCapacity)
    }

    mutating func trees(for members: [SplitMember]) -> [SplitLayoutTree] {
        guard members.count == SplitGroup.maximumMembers,
              Set(members.map(\.memberID)).count == members.count else {
            return []
        }

        let key = CacheKey(members: members)
        if let cached = treesByKey[key] {
            return cached
        }

        var seen = Set<SplitLayoutTree>()
        var trees: [SplitLayoutTree] = []

        func append(_ tree: SplitLayoutTree) {
            guard let canonical = SplitLayoutReconciler
                .canonicalizedForTiles(tree),
                seen.insert(canonical).inserted else {
                return
            }
            trees.append(canonical)
        }

        for rootAxis in [SplitAxis.row, .column] {
            forEachPermutation(of: members) { permutation in
                let childAxis = perpendicularAxis(to: rootAxis)
                append(
                    .split(
                        axis: rootAxis,
                        weight: 1,
                        children: [
                            equalLeafSplit(
                                axis: childAxis,
                                members: Array(permutation[0..<2]),
                                weight: 0.5
                            ),
                            equalLeafSplit(
                                axis: childAxis,
                                members: Array(permutation[2..<4]),
                                weight: 0.5
                            ),
                        ]
                    )
                )

                append(
                    .split(
                        axis: rootAxis,
                        weight: 1,
                        children: [
                            equalLeafSplit(
                                axis: childAxis,
                                members: Array(permutation[0..<3]),
                                weight: 0.5
                            ),
                            .leaf(member: permutation[3], weight: 0.5),
                        ]
                    )
                )
                append(
                    .split(
                        axis: rootAxis,
                        weight: 1,
                        children: [
                            .leaf(member: permutation[0], weight: 0.5),
                            equalLeafSplit(
                                axis: childAxis,
                                members: Array(permutation[1..<4]),
                                weight: 0.5
                            ),
                        ]
                    )
                )

                for splitIndex in 0..<3 {
                    var cursor = 0
                    let children: [SplitLayoutTree] = (0..<3).map { index in
                        if index == splitIndex {
                            let split = equalLeafSplit(
                                axis: childAxis,
                                members: Array(
                                    permutation[cursor..<cursor + 2]
                                ),
                                weight: 1.0 / 3.0
                            )
                            cursor += 2
                            return split
                        }
                        let leaf = SplitLayoutTree.leaf(
                            member: permutation[cursor],
                            weight: 1.0 / 3.0
                        )
                        cursor += 1
                        return leaf
                    }
                    append(
                        .split(
                            axis: rootAxis,
                            weight: 1,
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
        members: [SplitMember],
        weight: Double
    ) -> SplitLayoutTree {
        let childWeight = 1 / Double(members.count)
        return .split(
            axis: axis,
            weight: weight,
            children: members.map {
                .leaf(member: $0, weight: childWeight)
            }
        )
    }

    private func forEachPermutation(
        of members: [SplitMember],
        _ body: ([SplitMember]) -> Void
    ) {
        guard !members.isEmpty else {
            body([])
            return
        }

        var values = members
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
