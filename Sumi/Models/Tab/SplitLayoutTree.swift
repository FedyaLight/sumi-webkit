import Foundation

func uniqueSplitTabIdsPreservingOrder(_ tabIds: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    var result: [UUID] = []
    result.reserveCapacity(tabIds.count)
    for tabId in tabIds where seen.insert(tabId).inserted {
        result.append(tabId)
    }
    return result
}

/// Immutable split-tree value algebra with primitive structural mutations.
/// Pointer geometry, ratio policy, canonical recovery, and high-level drop
/// intent interpretation are handled by separate types.
indirect enum SplitLayoutTree: Codable, Equatable, Hashable, Sendable {
    case leaf(tabId: UUID, size: Double)
    case split(axis: SplitAxis, size: Double, children: [SplitLayoutTree])

    var sizeInParent: Double {
        switch self {
        case .leaf(_, let size), .split(_, let size, _):
            return size
        }
    }

    var tabIds: [UUID] {
        switch self {
        case .leaf(let tabId, _):
            return [tabId]
        case .split(_, _, let children):
            return children.flatMap(\.tabIds)
        }
    }

    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, let children):
            return children.reduce(0) { $0 + $1.leafCount }
        }
    }

    var isFlatFourLeafLine: Bool {
        guard case .split(_, _, let children) = self,
              children.count == SplitGroup.maximumTabs
        else {
            return false
        }
        return children.allSatisfy(Self.isLeaf)
    }

    func contains(_ tabId: UUID) -> Bool {
        switch self {
        case .leaf(let id, _):
            return id == tabId
        case .split(_, _, let children):
            return children.contains { $0.contains(tabId) }
        }
    }

    func hasSameStructure(as other: SplitLayoutTree) -> Bool {
        switch (self, other) {
        case (.leaf(let lhsTabId, _), .leaf(let rhsTabId, _)):
            return lhsTabId == rhsTabId
        case (.split(let lhsAxis, _, let lhsChildren), .split(let rhsAxis, _, let rhsChildren)):
            guard lhsAxis == rhsAxis, lhsChildren.count == rhsChildren.count else {
                return false
            }
            return zip(lhsChildren, rhsChildren).allSatisfy { lhs, rhs in
                lhs.hasSameStructure(as: rhs)
            }
        default:
            return false
        }
    }

    func node(at path: [Int]) -> SplitLayoutTree? {
        var node = self
        for index in path {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index)
            else {
                return nil
            }
            node = children[index]
        }
        return node
    }

    func removing(tabId: UUID) -> SplitLayoutTree? {
        switch self {
        case .leaf(let id, _):
            return id == tabId ? nil : self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { $0.removing(tabId: tabId) }
            if kept.isEmpty {
                return nil
            }
            if kept.count == 1 {
                return SplitLayoutSizing.settingSize(size, in: kept[0])
            }
            return SplitLayoutSizing.normalizingSiblingSizes(
                in: .split(axis: axis, size: size, children: kept)
            )
        }
    }

    func replacingTab(_ oldTabId: UUID, with newTabId: UUID) -> SplitLayoutTree {
        switch self {
        case .leaf(let tabId, let size):
            return .leaf(tabId: tabId == oldTabId ? newTabId : tabId, size: size)
        case .split(let axis, let size, let children):
            return .split(
                axis: axis,
                size: size,
                children: children.map { $0.replacingTab(oldTabId, with: newTabId) }
            )
        }
    }

    func swappingTabs(_ firstTabId: UUID, _ secondTabId: UUID) -> SplitLayoutTree {
        guard firstTabId != secondTabId else { return self }
        switch self {
        case .leaf(let tabId, let size):
            if tabId == firstTabId {
                return .leaf(tabId: secondTabId, size: size)
            }
            if tabId == secondTabId {
                return .leaf(tabId: firstTabId, size: size)
            }
            return self
        case .split(let axis, let size, let children):
            return .split(
                axis: axis,
                size: size,
                children: children.map { $0.swappingTabs(firstTabId, secondTabId) }
            )
        }
    }

    func movingTab(
        _ tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(tabId), contains(targetTabId), tabId != targetTabId else { return self }
        let remaining = tabIds.filter { $0 != tabId }
        guard remaining.contains(targetTabId), !remaining.isEmpty else { return self }
        let baseTree = removingForMove(tabId: tabId)
        let inserted = baseTree.inserting(
            tabId: tabId,
            relativeTo: targetTabId,
            side: side,
            equalizeInsertedAxis: false
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    func movingTabToRootEdge(_ tabId: UUID, side: SplitDropSide) -> SplitLayoutTree? {
        guard contains(tabId), side.insertionAxis != nil else { return nil }
        let baseTree = removingForMove(tabId: tabId)
        let inserted = baseTree.insertingAtRoot(
            tabId: tabId,
            side: side,
            equalizeInsertedAxis: false
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    func removingForMove(tabId: UUID) -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { child -> SplitLayoutTree? in
                guard child.contains(tabId) else { return child }
                return child.removingForMoveIfPresent(tabId: tabId)
            }
            guard kept.count > 1 else {
                return SplitLayoutSizing.settingSize(size, in: kept.first ?? self)
            }
            return SplitLayoutSizing.normalizingSiblingSizes(
                in: .split(axis: axis, size: size, children: kept)
            )
        }
    }

    func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree {
        guard let axis = side.insertionAxis else {
            return replacingTab(targetTabId, with: tabId)
        }
        let inserted = inserting(
            tabId: tabId,
            relativeTo: targetTabId,
            axis: axis,
            before: side == .left || side == .top,
            equalizeInsertedAxis: equalizeInsertedAxis
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
            ?? SplitLayoutSizing.normalizingSiblingSizes(in: inserted)
    }

    func insertingAtRoot(
        tabId: UUID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree {
        guard let insertionAxis = side.insertionAxis else { return self }
        let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 1)
        let insertBefore = side == .left || side == .top

        if case .split(let axis, let size, let children) = self, axis == insertionAxis {
            var updated = equalizeInsertedAxis
                ? children.map { SplitLayoutSizing.settingSize(1, in: $0) }
                : children
            if insertBefore {
                updated.insert(incoming, at: 0)
            } else {
                updated.append(incoming)
            }
            let inserted = SplitLayoutTree.split(axis: axis, size: size, children: updated)
            return SplitLayoutReconciler.canonicalizedForTiles(inserted)
                ?? SplitLayoutSizing.normalizingSiblingSizes(in: inserted)
        }

        let existing = SplitLayoutSizing.settingSize(1, in: self)
        let inserted = SplitLayoutTree.split(
            axis: insertionAxis,
            size: sizeInParent,
            children: insertBefore ? [incoming, existing] : [existing, incoming]
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
            ?? SplitLayoutSizing.normalizingSiblingSizes(in: inserted)
    }

    private func removingForMoveIfPresent(tabId: UUID) -> SplitLayoutTree? {
        switch self {
        case .leaf(let id, _):
            return id == tabId ? nil : self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { $0.removingForMoveIfPresent(tabId: tabId) }
            guard !kept.isEmpty else { return nil }
            guard kept.count > 1 else {
                return SplitLayoutSizing.settingSize(size, in: kept[0])
            }
            return SplitLayoutSizing.normalizingSiblingSizes(
                in: .split(axis: axis, size: size, children: kept)
            )
        }
    }

    private func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        axis insertionAxis: SplitAxis,
        before: Bool,
        equalizeInsertedAxis: Bool
    ) -> SplitLayoutTree {
        switch self {
        case .leaf(let existingTabId, let size):
            guard existingTabId == targetTabId else { return self }
            let existing = SplitLayoutTree.leaf(tabId: existingTabId, size: 0.5)
            let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: size,
                children: before ? [incoming, existing] : [existing, incoming]
            )

        case .split(let axis, let size, let children):
            if axis == insertionAxis,
               let targetIndex = children.firstIndex(where: {
                   $0.contains(targetTabId) && $0.leafCount == 1
               }) {
                var updated = children
                let insertionIndex = before ? targetIndex : targetIndex + 1
                updated.insert(.leaf(tabId: tabId, size: 1), at: insertionIndex)
                let split = SplitLayoutTree.split(axis: axis, size: size, children: updated)
                return equalizeInsertedAxis
                    ? SplitLayoutSizing.equalizingImmediateChildSizes(in: split)
                    : split
            }

            return .split(
                axis: axis,
                size: size,
                children: children.map {
                    $0.contains(targetTabId)
                        ? $0.inserting(
                            tabId: tabId,
                            relativeTo: targetTabId,
                            axis: insertionAxis,
                            before: before,
                            equalizeInsertedAxis: equalizeInsertedAxis
                        )
                        : $0
                }
            )
        }
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
