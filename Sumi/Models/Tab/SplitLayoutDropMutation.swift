import CoreGraphics
import Foundation
import SumiDomain

/// Applies an already-resolved pointer intent to the durable layout algebra.
/// Hit testing and window-local tab projection stay outside this component.
enum SplitLayoutDropMutation {
    struct Resolution: Equatable {
        let target: SplitDropTarget
        let layoutTree: SplitLayoutTree
    }

    private struct ThreeLeafPlane {
        let index: Int
        let axis: SplitAxis
        let weight: Double
        let leaves: [(member: SplitMember, weight: Double)]
    }

    private struct SingletonLeaf {
        let index: Int
        let member: SplitMember
        let weight: Double
    }

    private struct MixedThreeOneStructure {
        let rootAxis: SplitAxis
        let rootWeight: Double
        let children: [SplitLayoutTree]
        let plane: ThreeLeafPlane
        let singleton: SingletonLeaf
    }

    static func resolve(
        in tree: SplitLayoutTree,
        draggedMember: SplitMember,
        target: SplitDropTarget,
        bounds: CGRect
    ) -> Resolution? {
        let draggedMemberID = draggedMember.memberID
        let original = SplitLayoutReconciler.canonicalizedForTiles(tree) ?? tree
        let structuralMember = original.member(for: draggedMemberID)
            ?? draggedMember
        let resolvedTree = target.resolvedLayoutTree?
            .contains(draggedMemberID) == true
            ? target.resolvedLayoutTree
            : resolvingTileDrop(
                in: original,
                member: structuralMember,
                target: target
            )
        guard let resolvedTree,
              let canonicalTree = SplitLayoutReconciler
              .canonicalTreePreservingWeights(resolvedTree) else {
            return nil
        }
        let dropTree = target.side == .center
            ? canonicalTree
            : SplitLayoutSizing.equalizingAllSiblingWeights(in: canonicalTree)
        if tree.contains(draggedMemberID),
           dropTree.hasSameStructure(as: original) {
            return nil
        }
        guard let targetRect = SplitLayoutGeometry.leafRect(
            for: draggedMemberID,
            in: dropTree,
            rect: bounds
        ) else {
            return nil
        }
        return Resolution(
            target: target.resolving(
                targetRect: targetRect,
                resolvedLayoutTree: dropTree
            ),
            layoutTree: dropTree
        )
    }

    private static func resolvingTileDrop(
        in tree: SplitLayoutTree,
        member: SplitMember,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        guard target.side != .center else {
            return resolvingCenterDrop(
                in: tree,
                member: member,
                targetMemberID: target.targetMemberID
            )
        }

        switch target.intent {
        case .siblingEdge:
            return resolvingSiblingDrop(in: tree, member: member, target: target)
        case .flatFourPair:
            return pairingFlatFour(
                in: tree,
                member: member,
                targetMemberID: target.targetMemberID,
                side: target.side
            )
        case .flatThreePair:
            return pairingFlatThree(
                in: tree,
                member: member,
                targetMemberID: target.targetMemberID,
                side: target.side
            )
        case .flatFourReorder:
            return reorderingFlatFour(
                in: tree,
                memberID: member.memberID,
                targetMemberID: target.targetMemberID,
                side: target.side
            )
        case .mixedThreeOnePair:
            return pairingMixedThreeOne(
                in: tree,
                memberID: member.memberID,
                targetMemberID: target.targetMemberID,
                side: target.side
            )
        default:
            return resolvingPlaneDrop(in: tree, member: member, target: target)
        }
    }

    private static func resolvingCenterDrop(
        in tree: SplitLayoutTree,
        member: SplitMember,
        targetMemberID: SplitMemberID
    ) -> SplitLayoutTree? {
        let candidate: SplitLayoutTree?
        if tree.contains(member.memberID) {
            candidate = tree.swappingMembers(
                member.memberID,
                targetMemberID
            )
        } else {
            candidate = tree.replacingMember(targetMemberID, with: member)
        }
        return candidate.flatMap(
            SplitLayoutReconciler.canonicalTreePreservingWeights
        )
    }

    private static func resolvingSiblingDrop(
        in tree: SplitLayoutTree,
        member: SplitMember,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        let candidate: SplitLayoutTree?
        if tree.contains(member.memberID) {
            candidate = tree.movingMember(
                member.memberID,
                relativeTo: target.targetMemberID,
                side: target.side
            )
        } else {
            candidate = tree.inserting(
                member,
                relativeTo: target.targetMemberID,
                side: target.side
            )
        }
        return candidate.flatMap(
            SplitLayoutReconciler.canonicalTreePreservingWeights
        )
    }

    private static func resolvingPlaneDrop(
        in tree: SplitLayoutTree,
        member: SplitMember,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        let memberID = member.memberID
        let originalTargetIDs = tree.node(at: target.planePath)?.memberIDs ?? []
        let base: SplitLayoutTree
        var insertionPath = target.planePath
        if tree.contains(memberID) {
            let targetIDsAfterMove = originalTargetIDs.filter { $0 != memberID }
            guard !targetIDsAfterMove.isEmpty,
                  let remaining = tree.removing(memberID: memberID) else {
                return nil
            }
            base = remaining
            if let adjustedPath = pathForNode(
                in: base,
                withMemberIDs: targetIDsAfterMove
            ) {
                insertionPath = adjustedPath
            } else if base.node(at: insertionPath) == nil {
                return nil
            }
        } else {
            base = tree
        }

        if target.intent == .rootEdge,
           let insertionAxis = target.side.insertionAxis,
           SplitLayoutGeometry.hasSecondaryPlane(in: base),
           case .split(let axis, _, _) = base,
           axis == insertionAxis {
            var members = base.members
            if target.side.insertsBeforeTarget {
                members.insert(member, at: 0)
            } else {
                members.append(member)
            }
            guard let equalTree = SplitLayoutFactory.equalSplit(
                axis: insertionAxis,
                members: members
            ) else {
                return nil
            }
            return SplitLayoutReconciler.canonicalTreePreservingWeights(
                equalTree
            )
        }

        guard let inserted = insertingTile(
            in: base,
            member: member,
            at: insertionPath,
            side: target.side
        ),
        inserted.memberIDs.count <= SplitGroup.maximumMembers,
        Set(inserted.memberIDs).count == inserted.memberIDs.count else {
            return nil
        }
        return SplitLayoutReconciler.canonicalTreePreservingWeights(inserted)
    }

    private static func pairingFlatThree(
        in tree: SplitLayoutTree,
        member: SplitMember,
        targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        let memberID = member.memberID
        guard tree.contains(targetMemberID),
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootWeight, let children) = tree,
              children.count == 3,
              children.allSatisfy(isLeaf),
              insertionAxis != rootAxis,
              memberID != targetMemberID else {
            return nil
        }

        let leafChildren = leafMembers(in: children)
        guard leafChildren.count == children.count,
              leafChildren.contains(where: {
                  $0.member.memberID == targetMemberID
              }) else {
            return nil
        }
        let pairedMembers = side.insertsBeforeTarget
            ? [member, tree.member(for: targetMemberID)].compactMap { $0 }
            : [tree.member(for: targetMemberID), member].compactMap { $0 }
        guard let pairedPlane = SplitLayoutFactory.equalSplit(
            axis: insertionAxis,
            members: pairedMembers
        ) else {
            return nil
        }
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if tree.contains(memberID), leaf.member.memberID == memberID {
                return nil
            }
            if leaf.member.memberID == targetMemberID {
                return SplitLayoutSizing.settingWeight(
                    leaf.weight,
                    in: pairedPlane
                )
            }
            return .leaf(member: leaf.member, weight: leaf.weight)
        }
        guard !tree.contains(memberID) || updatedChildren.count == 2 else {
            return nil
        }
        return SplitLayoutReconciler.canonicalTreePreservingWeights(
            .split(
                axis: rootAxis,
                weight: rootWeight,
                children: updatedChildren
            )
        )
    }

    private static func pairingFlatFour(
        in tree: SplitLayoutTree,
        member: SplitMember,
        targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        let memberID = member.memberID
        guard tree.contains(memberID),
              tree.contains(targetMemberID),
              memberID != targetMemberID,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootWeight, let children) = tree,
              children.count == SplitGroup.maximumMembers,
              children.allSatisfy(isLeaf),
              insertionAxis != rootAxis else {
            return nil
        }

        let leafChildren = leafMembers(in: children)
        guard leafChildren.count == children.count,
              let targetMember = tree.member(for: targetMemberID),
              let pairedPlane = SplitLayoutFactory.equalSplit(
                  axis: insertionAxis,
                  members: side.insertsBeforeTarget
                      ? [member, targetMember]
                      : [targetMember, member]
              ) else {
            return nil
        }
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if leaf.member.memberID == memberID {
                return nil
            }
            if leaf.member.memberID == targetMemberID {
                return SplitLayoutSizing.settingWeight(
                    leaf.weight,
                    in: pairedPlane
                )
            }
            return .leaf(member: leaf.member, weight: leaf.weight)
        }
        guard updatedChildren.count == 3 else { return nil }
        return SplitLayoutReconciler.canonicalTreePreservingWeights(
            .split(
                axis: rootAxis,
                weight: rootWeight,
                children: updatedChildren
            )
        )
    }

    private static func pairingMixedThreeOne(
        in tree: SplitLayoutTree,
        memberID: SplitMemberID,
        targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(memberID),
              tree.contains(targetMemberID),
              memberID != targetMemberID,
              let insertionAxis = side.insertionAxis,
              let structure = mixedThreeOneStructure(in: tree),
              let draggedMember = tree.member(for: memberID),
              let targetMember = tree.member(for: targetMemberID) else {
            return nil
        }
        let splitInfo = structure.plane
        let singleton = structure.singleton
        let splitIDs = splitInfo.leaves.map(\.member.memberID)
        let draggedIsSingleton = singleton.member.memberID == memberID
            && splitIDs.contains(targetMemberID)
        let targetIsSingleton = singleton.member.memberID == targetMemberID
            && splitIDs.contains(memberID)
        guard draggedIsSingleton || targetIsSingleton else { return nil }

        let pairedMembers = side.insertsBeforeTarget
            ? [draggedMember, targetMember]
            : [targetMember, draggedMember]
        if insertionAxis != splitInfo.axis {
            let replacedMemberID = draggedIsSingleton
                ? targetMemberID
                : memberID
            guard let pairedPlane = SplitLayoutFactory.equalSplit(
                axis: insertionAxis,
                members: pairedMembers
            ) else {
                return nil
            }
            let updated = splitInfo.leaves.map { leaf -> SplitLayoutTree in
                if leaf.member.memberID == replacedMemberID {
                    return SplitLayoutSizing.settingWeight(
                        leaf.weight,
                        in: pairedPlane
                    )
                }
                return .leaf(member: leaf.member, weight: leaf.weight)
            }
            return SplitLayoutReconciler.canonicalTreePreservingWeights(
                .split(
                    axis: splitInfo.axis,
                    weight: structure.rootWeight,
                    children: updated
                )
            )
        }

        let remainingMembers = splitInfo.leaves
            .map(\.member)
            .filter {
                $0.memberID != memberID && $0.memberID != targetMemberID
            }
        guard remainingMembers.count == 2,
              let pairedPlane = SplitLayoutFactory.equalSplit(
                  axis: splitInfo.axis,
                  members: pairedMembers
              ),
              let remainingPlane = SplitLayoutFactory.equalSplit(
                  axis: splitInfo.axis,
                  members: remainingMembers
              ) else {
            return nil
        }

        var updated = structure.children
        if draggedIsSingleton {
            updated[splitInfo.index] = SplitLayoutSizing.settingWeight(
                splitInfo.weight,
                in: pairedPlane
            )
            updated[singleton.index] = SplitLayoutSizing.settingWeight(
                singleton.weight,
                in: remainingPlane
            )
        } else {
            updated[splitInfo.index] = SplitLayoutSizing.settingWeight(
                splitInfo.weight,
                in: remainingPlane
            )
            updated[singleton.index] = SplitLayoutSizing.settingWeight(
                singleton.weight,
                in: pairedPlane
            )
        }

        return SplitLayoutReconciler.canonicalTreePreservingWeights(
            .split(
                axis: structure.rootAxis,
                weight: structure.rootWeight,
                children: updated
            )
        )
    }

    private static func mixedThreeOneStructure(
        in tree: SplitLayoutTree
    ) -> MixedThreeOneStructure? {
        guard case .split(let rootAxis, let rootWeight, let children) = tree,
              children.count == 2 else {
            return nil
        }
        var plane: ThreeLeafPlane?
        var singleton: SingletonLeaf?
        for (index, child) in children.enumerated() {
            switch child {
            case .leaf(let member, let weight):
                singleton = SingletonLeaf(
                    index: index,
                    member: member,
                    weight: weight
                )
            case .split(let axis, let weight, let grandchildren):
                let leaves = leafMembers(in: grandchildren)
                if leaves.count == 3 {
                    plane = ThreeLeafPlane(
                        index: index,
                        axis: axis,
                        weight: weight,
                        leaves: leaves
                    )
                }
            }
        }
        guard let plane, let singleton else { return nil }
        return MixedThreeOneStructure(
            rootAxis: rootAxis,
            rootWeight: rootWeight,
            children: children,
            plane: plane,
            singleton: singleton
        )
    }

    private static func reorderingFlatFour(
        in tree: SplitLayoutTree,
        memberID: SplitMemberID,
        targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(memberID),
              tree.contains(targetMemberID),
              memberID != targetMemberID,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootWeight, let children) = tree,
              children.count == SplitGroup.maximumMembers,
              children.allSatisfy(isLeaf),
              insertionAxis == rootAxis,
              let movingMember = tree.member(for: memberID) else {
            return nil
        }

        var members = tree.members.filter { $0.memberID != memberID }
        guard let targetIndex = members.firstIndex(where: {
            $0.memberID == targetMemberID
        }) else {
            return nil
        }
        members.insert(
            movingMember,
            at: side.insertsBeforeTarget ? targetIndex : targetIndex + 1
        )
        guard members.map(\.memberID) != tree.memberIDs,
              let equalTree = SplitLayoutFactory.equalSplit(
                  axis: rootAxis,
                  members: members
              ) else {
            return nil
        }
        return SplitLayoutReconciler.canonicalTreePreservingWeights(
            SplitLayoutSizing.settingWeight(rootWeight, in: equalTree)
        )
    }

    private static func pathForNode(
        in tree: SplitLayoutTree,
        withMemberIDs memberIDs: [SplitMemberID]
    ) -> [Int]? {
        guard !memberIDs.isEmpty else { return nil }
        if tree.memberIDs == memberIDs {
            return []
        }
        guard case .split(_, _, let children) = tree else { return nil }
        for (index, child) in children.enumerated() {
            if let childPath = pathForNode(
                in: child,
                withMemberIDs: memberIDs
            ) {
                return [index] + childPath
            }
        }
        return nil
    }

    private static func insertingTile(
        in tree: SplitLayoutTree,
        member: SplitMember,
        at path: [Int],
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard !path.isEmpty else {
            return insertingTileAtCurrentNode(
                in: tree,
                member: member,
                side: side
            )
        }
        guard case .split(let axis, let weight, let children) = tree,
              let index = path.first,
              children.indices.contains(index) else {
            return nil
        }
        var updated = children
        guard let insertedChild = insertingTile(
            in: updated[index],
            member: member,
            at: Array(path.dropFirst()),
            side: side
        ) else {
            return nil
        }
        updated[index] = insertedChild
        return .split(axis: axis, weight: weight, children: updated)
    }

    private static func insertingTileAtCurrentNode(
        in tree: SplitLayoutTree,
        member: SplitMember,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard let insertionAxis = side.insertionAxis else { return nil }
        let incoming = SplitLayoutTree.leaf(member: member, weight: 1)

        switch tree {
        case .leaf(let existingMember, let weight):
            let existing = SplitLayoutTree.leaf(
                member: existingMember,
                weight: 0.5
            )
            let inserted = SplitLayoutTree.leaf(member: member, weight: 0.5)
            return .split(
                axis: insertionAxis,
                weight: weight,
                children: side.insertsBeforeTarget
                    ? [inserted, existing]
                    : [existing, inserted]
            )

        case .split(let axis, let weight, let children):
            if axis == insertionAxis {
                var updated = children.map {
                    SplitLayoutSizing.settingWeight(1, in: $0)
                }
                if side.insertsBeforeTarget {
                    updated.insert(incoming, at: 0)
                } else {
                    updated.append(incoming)
                }
                return SplitLayoutSizing.equalizingImmediateChildWeights(
                    in: .split(
                        axis: axis,
                        weight: weight,
                        children: updated
                    )
                )
            }

            let existing = SplitLayoutSizing.settingWeight(0.5, in: tree)
            let inserted = SplitLayoutTree.leaf(member: member, weight: 0.5)
            return .split(
                axis: insertionAxis,
                weight: tree.weightInParent,
                children: side.insertsBeforeTarget
                    ? [inserted, existing]
                    : [existing, inserted]
            )
        }
    }

    private static func leafMembers(
        in children: [SplitLayoutTree]
    ) -> [(member: SplitMember, weight: Double)] {
        children.compactMap { child in
            if case .leaf(let member, let weight) = child {
                return (member, weight)
            }
            return nil
        }
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
