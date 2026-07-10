import Foundation

enum SplitDropLayoutEligibility {
    struct MixedThreeOne {
        let splitTabIds: Set<UUID>
        let singletonTabId: UUID

        func canPair(draggedTabId: UUID, targetTabId: UUID) -> Bool {
            (draggedTabId == singletonTabId && splitTabIds.contains(targetTabId))
                || (targetTabId == singletonTabId && splitTabIds.contains(draggedTabId))
        }
    }

    static func flatAxis(
        in tree: SplitLayoutTree,
        childCount: Int? = nil
    ) -> SplitAxis? {
        guard case .split(let axis, _, let children) = tree,
              childCount.map({ children.count == $0 }) ?? true,
              children.allSatisfy(isLeaf)
        else {
            return nil
        }
        return axis
    }

    static func mixedThreeOne(in tree: SplitLayoutTree) -> MixedThreeOne? {
        guard case .split(_, _, let children) = tree,
              children.count == 2
        else {
            return nil
        }

        var splitTabIds: Set<UUID> = []
        var singletonTabId: UUID?
        for child in children {
            switch child {
            case .leaf(let tabId, _):
                singletonTabId = tabId
            case .split(_, _, let grandchildren):
                let leafIds = grandchildren.compactMap { grandchild -> UUID? in
                    if case .leaf(let tabId, _) = grandchild {
                        return tabId
                    }
                    return nil
                }
                if leafIds.count == 3 {
                    splitTabIds = Set(leafIds)
                }
            }
        }

        guard splitTabIds.isEmpty == false, let singletonTabId else {
            return nil
        }
        return MixedThreeOne(
            splitTabIds: splitTabIds,
            singletonTabId: singletonTabId
        )
    }

    static func parentAxis(
        for path: [Int],
        in tree: SplitLayoutTree
    ) -> SplitAxis? {
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

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
