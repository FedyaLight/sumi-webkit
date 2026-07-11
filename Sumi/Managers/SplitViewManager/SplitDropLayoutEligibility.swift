import Foundation
import SumiDomain

enum SplitDropLayoutEligibility {
    struct MixedThreeOne {
        let splitMemberIDs: Set<SplitMemberID>
        let singletonMemberID: SplitMemberID

        func canPair(
            draggedMemberID: SplitMemberID,
            targetMemberID: SplitMemberID
        ) -> Bool {
            (draggedMemberID == singletonMemberID
                && splitMemberIDs.contains(targetMemberID))
                || (targetMemberID == singletonMemberID
                    && splitMemberIDs.contains(draggedMemberID))
        }
    }

    static func flatAxis(
        in tree: SplitLayoutTree,
        childCount: Int? = nil
    ) -> SplitAxis? {
        guard case .split(let axis, _, let children) = tree,
              childCount.map({ children.count == $0 }) ?? true,
              children.allSatisfy(isLeaf) else {
            return nil
        }
        return axis
    }

    static func mixedThreeOne(in tree: SplitLayoutTree) -> MixedThreeOne? {
        guard case .split(_, _, let children) = tree,
              children.count == 2 else {
            return nil
        }

        var splitMemberIDs: Set<SplitMemberID> = []
        var singletonMemberID: SplitMemberID?
        for child in children {
            switch child {
            case .leaf(let member, _):
                singletonMemberID = member.memberID
            case .split(_, _, let grandchildren):
                let leafIDs = grandchildren.compactMap { grandchild in
                    if case .leaf(let member, _) = grandchild {
                        return member.memberID
                    }
                    return nil
                }
                if leafIDs.count == 3 {
                    splitMemberIDs = Set(leafIDs)
                }
            }
        }

        guard !splitMemberIDs.isEmpty, let singletonMemberID else {
            return nil
        }
        return MixedThreeOne(
            splitMemberIDs: splitMemberIDs,
            singletonMemberID: singletonMemberID
        )
    }

    static func parentAxis(
        for path: [Int],
        in tree: SplitLayoutTree
    ) -> SplitAxis? {
        guard !path.isEmpty else { return nil }
        var node = tree
        for index in path.dropLast() {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index) else {
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
