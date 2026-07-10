import CoreGraphics
import Foundation

/// Applies an already-resolved drag intent to a layout tree. Hit testing and
/// target selection live outside this component.
enum SplitLayoutDropMutation {
    struct Resolution: Equatable {
        let target: SplitDropTarget
        let layoutTree: SplitLayoutTree
    }

    private struct ThreeLeafPlane {
        let index: Int
        let axis: SplitAxis
        let size: Double
        let leaves: [(tabId: UUID, size: Double)]
    }

    private struct SingletonLeaf {
        let index: Int
        let tabId: UUID
        let size: Double
    }

    private struct MixedThreeOneStructure {
        let rootAxis: SplitAxis
        let rootSize: Double
        let children: [SplitLayoutTree]
        let plane: ThreeLeafPlane
        let singleton: SingletonLeaf
    }

    static func resolve(
        in tree: SplitLayoutTree,
        draggedTabId: UUID,
        target: SplitDropTarget,
        bounds: CGRect
    ) -> Resolution? {
        let original = SplitLayoutReconciler.canonicalizedForTiles(tree) ?? tree
        let resolvedTree = target.resolvedLayoutTree?.contains(draggedTabId) == true
            ? target.resolvedLayoutTree
            : resolvingTileDrop(in: original, tabId: draggedTabId, target: target)
        guard let resolvedTree,
              let canonicalTree = SplitLayoutReconciler.canonicalTreePreservingSizes(resolvedTree)
        else {
            return nil
        }
        let dropTree = target.side == .center
            ? canonicalTree
            : SplitLayoutSizing.equalizingStructuralDropSizes(in: canonicalTree)
        if tree.contains(draggedTabId),
           dropTree.hasSameStructure(as: original) {
            return nil
        }
        guard let targetRect = SplitLayoutGeometry.leafRect(
            for: draggedTabId,
            in: dropTree,
            rect: bounds
        ) else {
            return nil
        }
        return Resolution(
            target: target.resolving(targetRect: targetRect, resolvedLayoutTree: dropTree),
            layoutTree: dropTree
        )
    }

    private static func resolvingTileDrop(
        in tree: SplitLayoutTree,
        tabId: UUID,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        guard target.side != .center else {
            return resolvingCenterDrop(in: tree, tabId: tabId, targetTabId: target.tabId)
        }

        switch target.intent {
        case .siblingEdge:
            return resolvingSiblingDrop(in: tree, tabId: tabId, target: target)
        case .flatFourPair:
            return pairingFlatFour(
                in: tree,
                tabId: tabId,
                targetTabId: target.tabId,
                side: target.side
            )
        case .flatThreePair:
            return pairingFlatThree(
                in: tree,
                tabId: tabId,
                targetTabId: target.tabId,
                side: target.side
            )
        case .flatFourReorder:
            return reorderingFlatFour(
                in: tree,
                tabId: tabId,
                targetTabId: target.tabId,
                side: target.side
            )
        case .mixedThreeOnePair:
            return pairingMixedThreeOne(
                in: tree,
                tabId: tabId,
                targetTabId: target.tabId,
                side: target.side
            )
        default:
            return resolvingPlaneDrop(in: tree, tabId: tabId, target: target)
        }
    }

    private static func resolvingCenterDrop(
        in tree: SplitLayoutTree,
        tabId: UUID,
        targetTabId: UUID
    ) -> SplitLayoutTree? {
        if tree.contains(tabId) {
            guard tabId != targetTabId else { return nil }
            return SplitLayoutReconciler.canonicalTreePreservingSizes(
                tree.swappingTabs(tabId, targetTabId)
            )
        }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            tree.replacingTab(targetTabId, with: tabId)
        )
    }

    private static func resolvingSiblingDrop(
        in tree: SplitLayoutTree,
        tabId: UUID,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        if tree.contains(tabId) {
            guard let moved = tree.movingTab(
                tabId,
                relativeTo: target.tabId,
                side: target.side
            ) else {
                return nil
            }
            return SplitLayoutReconciler.canonicalTreePreservingSizes(moved)
        }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            tree.inserting(tabId: tabId, relativeTo: target.tabId, side: target.side)
        )
    }

    private static func resolvingPlaneDrop(
        in tree: SplitLayoutTree,
        tabId: UUID,
        target: SplitDropTarget
    ) -> SplitLayoutTree? {
        let originalTargetIds = tree.node(at: target.planePath)?.tabIds ?? []
        let base: SplitLayoutTree
        var insertionPath = target.planePath
        if tree.contains(tabId) {
            let targetIdsAfterMove = originalTargetIds.filter { $0 != tabId }
            guard !targetIdsAfterMove.isEmpty else { return nil }
            base = tree.removingForMove(tabId: tabId)
            if let adjustedPath = pathForNode(in: base, withTabIds: targetIdsAfterMove) {
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
            var ids = base.tabIds
            if target.side == .left || target.side == .top {
                ids.insert(tabId, at: 0)
            } else {
                ids.append(tabId)
            }
            return SplitLayoutReconciler.canonicalTreePreservingSizes(
                SplitLayoutFactory.equalSplit(axis: insertionAxis, tabIds: ids)
            )
        }

        guard let inserted = insertingTile(
            in: base,
            tabId: tabId,
            at: insertionPath,
            side: target.side
        ),
        inserted.tabIds.count <= SplitGroup.maximumTabs,
        Set(inserted.tabIds).count == inserted.tabIds.count
        else {
            return nil
        }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(inserted)
    }

    private static func pairingFlatThree(
        in tree: SplitLayoutTree,
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(targetTabId),
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = tree,
              children.count == 3,
              children.allSatisfy(isLeaf),
              insertionAxis != rootAxis,
              tabId != targetTabId
        else {
            return nil
        }

        let leafChildren: [(tabId: UUID, size: Double)] = children.compactMap { child in
            if case .leaf(let id, let size) = child {
                return (id, size)
            }
            return nil
        }
        guard leafChildren.count == children.count,
              leafChildren.contains(where: { $0.tabId == targetTabId })
        else {
            return nil
        }
        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]

        let pairedPlane = SplitLayoutFactory.equalSplit(axis: insertionAxis, tabIds: pairedIds)
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if tree.contains(tabId), leaf.tabId == tabId {
                return nil
            }
            if leaf.tabId == targetTabId {
                return SplitLayoutSizing.settingSize(leaf.size, in: pairedPlane)
            }
            return .leaf(tabId: leaf.tabId, size: leaf.size)
        }
        guard !tree.contains(tabId) || updatedChildren.count == 2 else {
            return nil
        }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            .split(axis: rootAxis, size: rootSize, children: updatedChildren)
        )
    }

    private static func pairingFlatFour(
        in tree: SplitLayoutTree,
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(tabId),
              tree.contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = tree,
              children.count == SplitGroup.maximumTabs,
              children.allSatisfy(isLeaf),
              insertionAxis != rootAxis
        else {
            return nil
        }

        let leafChildren: [(tabId: UUID, size: Double)] = children.compactMap { child in
            if case .leaf(let id, let size) = child {
                return (id, size)
            }
            return nil
        }
        guard leafChildren.count == children.count,
              leafChildren.contains(where: { $0.tabId == targetTabId })
        else {
            return nil
        }
        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]

        let pairedPlane = SplitLayoutFactory.equalSplit(axis: insertionAxis, tabIds: pairedIds)
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if leaf.tabId == tabId {
                return nil
            }
            if leaf.tabId == targetTabId {
                return SplitLayoutSizing.settingSize(leaf.size, in: pairedPlane)
            }
            return .leaf(tabId: leaf.tabId, size: leaf.size)
        }
        guard updatedChildren.count == 3 else { return nil }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            .split(axis: rootAxis, size: rootSize, children: updatedChildren)
        )
    }

    private static func pairingMixedThreeOne(
        in tree: SplitLayoutTree,
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(tabId),
              tree.contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              let structure = mixedThreeOneStructure(in: tree)
        else {
            return nil
        }
        let splitInfo = structure.plane
        let leafInfo = structure.singleton

        let splitIds = splitInfo.leaves.map(\.tabId)
        let draggedIsSingleton = leafInfo.tabId == tabId && splitIds.contains(targetTabId)
        let targetIsSingleton = leafInfo.tabId == targetTabId && splitIds.contains(tabId)
        guard draggedIsSingleton || targetIsSingleton else { return nil }

        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]
        if insertionAxis != splitInfo.axis {
            let replacedTabId = draggedIsSingleton ? targetTabId : tabId
            let pairedPlane = SplitLayoutFactory.equalSplit(
                axis: insertionAxis,
                tabIds: pairedIds
            )
            let updated = splitInfo.leaves.map { leaf -> SplitLayoutTree in
                if leaf.tabId == replacedTabId {
                    return SplitLayoutSizing.settingSize(leaf.size, in: pairedPlane)
                }
                return .leaf(tabId: leaf.tabId, size: leaf.size)
            }
            return SplitLayoutReconciler.canonicalTreePreservingSizes(
                .split(axis: splitInfo.axis, size: structure.rootSize, children: updated)
            )
        }

        let remainingIds = splitIds.filter { $0 != tabId && $0 != targetTabId }
        guard remainingIds.count == 2 else { return nil }
        let pairedPlane = SplitLayoutFactory.equalSplit(
            axis: splitInfo.axis,
            tabIds: pairedIds
        )
        let remainingPlane = SplitLayoutFactory.equalSplit(
            axis: splitInfo.axis,
            tabIds: remainingIds
        )

        var updated = structure.children
        if draggedIsSingleton {
            updated[splitInfo.index] = SplitLayoutSizing.settingSize(
                splitInfo.size,
                in: pairedPlane
            )
            updated[leafInfo.index] = SplitLayoutSizing.settingSize(
                leafInfo.size,
                in: remainingPlane
            )
        } else {
            updated[splitInfo.index] = SplitLayoutSizing.settingSize(
                splitInfo.size,
                in: remainingPlane
            )
            updated[leafInfo.index] = SplitLayoutSizing.settingSize(
                leafInfo.size,
                in: pairedPlane
            )
        }

        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            .split(axis: structure.rootAxis, size: structure.rootSize, children: updated)
        )
    }

    private static func mixedThreeOneStructure(
        in tree: SplitLayoutTree
    ) -> MixedThreeOneStructure? {
        guard case .split(let rootAxis, let rootSize, let children) = tree,
              children.count == 2
        else {
            return nil
        }
        var plane: ThreeLeafPlane?
        var singleton: SingletonLeaf?
        for (index, child) in children.enumerated() {
            switch child {
            case .leaf(let id, let size):
                singleton = SingletonLeaf(index: index, tabId: id, size: size)
            case .split(let axis, let size, let grandchildren):
                let leaves: [(tabId: UUID, size: Double)] = grandchildren.compactMap { grandchild in
                    if case .leaf(let id, let leafSize) = grandchild {
                        return (id, leafSize)
                    }
                    return nil
                }
                if leaves.count == 3 {
                    plane = ThreeLeafPlane(
                        index: index,
                        axis: axis,
                        size: size,
                        leaves: leaves
                    )
                }
            }
        }
        guard let plane, let singleton else { return nil }
        return MixedThreeOneStructure(
            rootAxis: rootAxis,
            rootSize: rootSize,
            children: children,
            plane: plane,
            singleton: singleton
        )
    }

    private static func reorderingFlatFour(
        in tree: SplitLayoutTree,
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard tree.contains(tabId),
              tree.contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = tree,
              children.count == SplitGroup.maximumTabs,
              children.allSatisfy(isLeaf),
              insertionAxis == rootAxis
        else {
            return nil
        }

        var ids = tree.tabIds.filter { $0 != tabId }
        guard let targetIndex = ids.firstIndex(of: targetTabId) else { return nil }
        let insertBefore = side == .left || side == .top
        ids.insert(tabId, at: insertBefore ? targetIndex : targetIndex + 1)
        guard ids != tree.tabIds else { return nil }
        return SplitLayoutReconciler.canonicalTreePreservingSizes(
            SplitLayoutSizing.settingSize(
                rootSize,
                in: SplitLayoutFactory.equalSplit(axis: rootAxis, tabIds: ids)
            )
        )
    }

    private static func pathForNode(
        in tree: SplitLayoutTree,
        withTabIds ids: [UUID]
    ) -> [Int]? {
        guard !ids.isEmpty else { return nil }
        if tree.tabIds == ids {
            return []
        }
        guard case .split(_, _, let children) = tree else { return nil }
        for (index, child) in children.enumerated() {
            if let childPath = pathForNode(in: child, withTabIds: ids) {
                return [index] + childPath
            }
        }
        return nil
    }

    private static func insertingTile(
        in tree: SplitLayoutTree,
        tabId: UUID,
        at path: [Int],
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard !path.isEmpty else {
            return insertingTileAtCurrentNode(in: tree, tabId: tabId, side: side)
        }
        guard case .split(let axis, let size, let children) = tree,
              let index = path.first,
              children.indices.contains(index)
        else {
            return nil
        }
        var updated = children
        guard let insertedChild = insertingTile(
            in: updated[index],
            tabId: tabId,
            at: Array(path.dropFirst()),
            side: side
        ) else {
            return nil
        }
        updated[index] = insertedChild
        return .split(axis: axis, size: size, children: updated)
    }

    private static func insertingTileAtCurrentNode(
        in tree: SplitLayoutTree,
        tabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard let insertionAxis = side.insertionAxis else { return nil }
        let insertBefore = side == .left || side == .top
        let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 1)

        switch tree {
        case .leaf(let existingTabId, let size):
            let existing = SplitLayoutTree.leaf(tabId: existingTabId, size: 0.5)
            let inserted = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: size,
                children: insertBefore ? [inserted, existing] : [existing, inserted]
            )

        case .split(let axis, let size, let children):
            if axis == insertionAxis {
                var updated = children.map { SplitLayoutSizing.settingSize(1, in: $0) }
                if insertBefore {
                    updated.insert(incoming, at: 0)
                } else {
                    updated.append(incoming)
                }
                return SplitLayoutSizing.equalizingImmediateChildSizes(
                    in: .split(axis: axis, size: size, children: updated)
                )
            }

            let existing = SplitLayoutSizing.settingSize(0.5, in: tree)
            let inserted = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: tree.sizeInParent,
                children: insertBefore ? [inserted, existing] : [existing, inserted]
            )
        }
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
