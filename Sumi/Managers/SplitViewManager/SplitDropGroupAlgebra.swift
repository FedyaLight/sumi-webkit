import Foundation
import SumiDomain

/// Pure structural half of a split drop. Runtime materialization and commits
/// remain outside this value algebra.
enum SplitDropGroupAlgebra {
    static func resolvedTree(
        for member: SplitMember,
        in group: SumiDomain.SplitGroup,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        if let resolution = SplitLayoutDropMutation.resolve(
            in: group.layoutTree,
            draggedMember: member,
            target: target,
            bounds: target.targetRect
        ) {
            return resolution.layoutTree
        }
        if target.side == .center {
            return group.layoutTree.replacingMember(
                target.targetMemberID,
                with: member
            )
        }
        if target.scope == .group {
            return group.layoutTree.contains(member.memberID)
                ? group.layoutTree.movingMemberToRootEdge(
                    member.memberID,
                    side: target.side
                )
                : group.layoutTree.insertingAtRoot(
                    member,
                    side: target.side
                )
        }
        return group.layoutTree.contains(member.memberID)
            ? group.layoutTree.movingMember(
                member.memberID,
                relativeTo: target.targetMemberID,
                side: target.side
            )
            : group.layoutTree.inserting(
                member,
                relativeTo: target.targetMemberID,
                side: target.side
            )
    }

    static func replacingGroups(
        _ groups: [SumiDomain.SplitGroup],
        sourceGroup: SumiDomain.SplitGroup?,
        movingMemberID: SplitMemberID,
        targetGroup: SumiDomain.SplitGroup,
        replacementTarget: SumiDomain.SplitGroup
    ) -> [SumiDomain.SplitGroup] {
        guard replacementTarget.id == targetGroup.id,
              groups.contains(targetGroup),
              sourceGroup.map({ groups.contains($0) }) ?? true else {
            return groups
        }
        var result = removingSourceGroup(
            sourceGroup,
            memberID: movingMemberID,
            from: groups
        )
        guard let targetIndex = result.firstIndex(where: {
            $0.id == targetGroup.id
        }) else {
            return groups
        }
        result[targetIndex] = replacementTarget
        return result
    }

    static func removingSourceGroup(
        _ sourceGroup: SumiDomain.SplitGroup?,
        memberID: SplitMemberID?,
        from groups: [SumiDomain.SplitGroup]
    ) -> [SumiDomain.SplitGroup] {
        guard let sourceGroup, let memberID else { return groups }
        guard groups.contains(sourceGroup) else { return groups }
        return groups.compactMap { group in
            guard group.id == sourceGroup.id else { return group }
            return sourceGroup.removingMember(memberID)
        }
    }
}
