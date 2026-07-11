import Foundation

/// Immutable split-tree value algebra. It contains durable members only;
/// pointer geometry and window-local live-tab projection stay in the app.
public indirect enum SplitLayoutTree: Equatable, Hashable, Sendable {
    case leaf(member: SplitMember, weight: Double)
    case split(axis: SplitAxis, weight: Double, children: [SplitLayoutTree])

    private enum CodingKeys: String, CodingKey {
        case kind
        case member
        case weight
        case axis
        case children
    }

    private enum Kind: String, Codable {
        case leaf
        case split
    }

    public var weightInParent: Double {
        switch self {
        case .leaf(_, let weight), .split(_, let weight, _):
            return weight
        }
    }

    public var members: [SplitMember] {
        switch self {
        case .leaf(let member, _):
            return [member]
        case .split(_, _, let children):
            return children.flatMap(\.members)
        }
    }

    public var memberIDs: [SplitMemberID] {
        members.map(\.memberID)
    }

    public var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, let children):
            return children.reduce(0) { $0 + $1.leafCount }
        }
    }

    public var isFlatFourLeafLine: Bool {
        guard case .split(_, _, let children) = self,
              children.count == SplitGroup.maximumMembers else {
            return false
        }
        return children.allSatisfy(Self.isLeaf)
    }

    public func contains(_ memberID: SplitMemberID) -> Bool {
        member(for: memberID) != nil
    }

    public func member(for memberID: SplitMemberID) -> SplitMember? {
        switch self {
        case .leaf(let member, _):
            return member.memberID == memberID ? member : nil
        case .split(_, _, let children):
            return children.lazy.compactMap { $0.member(for: memberID) }.first
        }
    }

    public func hasSameStructure(as other: SplitLayoutTree) -> Bool {
        switch (self, other) {
        case (.leaf(let lhs, _), .leaf(let rhs, _)):
            return lhs.memberID == rhs.memberID
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

    public func node(at path: [Int]) -> SplitLayoutTree? {
        var node = self
        for index in path {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index) else {
                return nil
            }
            node = children[index]
        }
        return node
    }

    public func removing(memberID: SplitMemberID) -> SplitLayoutTree? {
        switch self {
        case .leaf(let member, _):
            return member.memberID == memberID ? nil : self
        case .split(let axis, let weight, let children):
            let kept = children.compactMap { $0.removing(memberID: memberID) }
            if kept.isEmpty {
                return nil
            }
            if kept.count == 1 {
                return SplitLayoutSizing.settingWeight(weight, in: kept[0])
            }
            return SplitLayoutSizing.normalizingSiblingWeights(
                in: .split(axis: axis, weight: weight, children: kept)
            )
        }
    }

    public func replacingMember(
        _ memberID: SplitMemberID,
        with replacement: SplitMember
    ) -> SplitLayoutTree? {
        guard contains(memberID),
              replacement.memberID == memberID || !contains(replacement.memberID) else {
            return nil
        }
        return replacingMemberUnchecked(memberID, with: replacement)
    }

    public func swappingMembers(
        _ firstMemberID: SplitMemberID,
        _ secondMemberID: SplitMemberID
    ) -> SplitLayoutTree? {
        guard firstMemberID != secondMemberID,
              let first = member(for: firstMemberID),
              let second = member(for: secondMemberID) else {
            return nil
        }
        return swappingMembersUnchecked(first, second)
    }

    public func movingMember(
        _ memberID: SplitMemberID,
        relativeTo targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard memberID != targetMemberID,
              let movingMember = member(for: memberID),
              contains(targetMemberID) else {
            return nil
        }
        if side == .center {
            return swappingMembers(memberID, targetMemberID)
        }
        let baseTree = removingForMove(memberID: memberID)
        guard let inserted = baseTree.insertingUnchecked(
            movingMember,
            relativeTo: targetMemberID,
            side: side,
            equalizeInsertedAxis: false
        ) else {
            return nil
        }
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    public func movingMemberToRootEdge(
        _ memberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard let movingMember = member(for: memberID),
              side.insertionAxis != nil else {
            return nil
        }
        let baseTree = removingForMove(memberID: memberID)
        let inserted = baseTree.insertingAtRootUnchecked(
            movingMember,
            side: side,
            equalizeInsertedAxis: false
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    public func inserting(
        _ member: SplitMember,
        relativeTo targetMemberID: SplitMemberID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree? {
        guard !contains(member.memberID),
              contains(targetMemberID) else {
            return nil
        }
        guard side == .center || leafCount < SplitGroup.maximumMembers else {
            return nil
        }
        guard let inserted = insertingUnchecked(
            member,
            relativeTo: targetMemberID,
            side: side,
            equalizeInsertedAxis: equalizeInsertedAxis
        ) else {
            return nil
        }
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    public func insertingAtRoot(
        _ member: SplitMember,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree? {
        guard !contains(member.memberID),
              leafCount < SplitGroup.maximumMembers,
              side.insertionAxis != nil else {
            return nil
        }
        let inserted = insertingAtRootUnchecked(
            member,
            side: side,
            equalizeInsertedAxis: equalizeInsertedAxis
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
    }

    private func replacingMemberUnchecked(
        _ memberID: SplitMemberID,
        with replacement: SplitMember
    ) -> SplitLayoutTree {
        switch self {
        case .leaf(let member, let weight):
            return .leaf(
                member: member.memberID == memberID ? replacement : member,
                weight: weight
            )
        case .split(let axis, let weight, let children):
            return .split(
                axis: axis,
                weight: weight,
                children: children.map {
                    $0.replacingMemberUnchecked(memberID, with: replacement)
                }
            )
        }
    }

    private func swappingMembersUnchecked(
        _ first: SplitMember,
        _ second: SplitMember
    ) -> SplitLayoutTree {
        switch self {
        case .leaf(let member, let weight):
            if member.memberID == first.memberID {
                return .leaf(member: second, weight: weight)
            }
            if member.memberID == second.memberID {
                return .leaf(member: first, weight: weight)
            }
            return self
        case .split(let axis, let weight, let children):
            return .split(
                axis: axis,
                weight: weight,
                children: children.map {
                    $0.swappingMembersUnchecked(first, second)
                }
            )
        }
    }

    private func removingForMove(memberID: SplitMemberID) -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let weight, let children):
            let kept = children.compactMap { child -> SplitLayoutTree? in
                guard child.contains(memberID) else { return child }
                return child.removingForMoveIfPresent(memberID: memberID)
            }
            guard kept.count > 1 else {
                return SplitLayoutSizing.settingWeight(weight, in: kept.first ?? self)
            }
            return SplitLayoutSizing.normalizingSiblingWeights(
                in: .split(axis: axis, weight: weight, children: kept)
            )
        }
    }

    private func removingForMoveIfPresent(
        memberID: SplitMemberID
    ) -> SplitLayoutTree? {
        switch self {
        case .leaf(let member, _):
            return member.memberID == memberID ? nil : self
        case .split(let axis, let weight, let children):
            let kept = children.compactMap {
                $0.removingForMoveIfPresent(memberID: memberID)
            }
            guard !kept.isEmpty else { return nil }
            guard kept.count > 1 else {
                return SplitLayoutSizing.settingWeight(weight, in: kept[0])
            }
            return SplitLayoutSizing.normalizingSiblingWeights(
                in: .split(axis: axis, weight: weight, children: kept)
            )
        }
    }

    private func insertingUnchecked(
        _ member: SplitMember,
        relativeTo targetMemberID: SplitMemberID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool
    ) -> SplitLayoutTree? {
        guard let insertionAxis = side.insertionAxis else {
            return replacingMember(targetMemberID, with: member)
        }
        return insertingUnchecked(
            member,
            relativeTo: targetMemberID,
            axis: insertionAxis,
            before: side.insertsBeforeTarget,
            equalizeInsertedAxis: equalizeInsertedAxis
        )
    }

    private func insertingAtRootUnchecked(
        _ member: SplitMember,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool
    ) -> SplitLayoutTree {
        guard let insertionAxis = side.insertionAxis else { return self }
        let incoming = SplitLayoutTree.leaf(member: member, weight: 1)

        if case .split(let axis, let weight, let children) = self,
           axis == insertionAxis {
            var updated = equalizeInsertedAxis
                ? children.map { SplitLayoutSizing.settingWeight(1, in: $0) }
                : children
            if side.insertsBeforeTarget {
                updated.insert(incoming, at: 0)
            } else {
                updated.append(incoming)
            }
            let inserted = SplitLayoutTree.split(
                axis: axis,
                weight: weight,
                children: updated
            )
            return SplitLayoutReconciler.canonicalizedForTiles(inserted)
                ?? SplitLayoutSizing.normalizingSiblingWeights(in: inserted)
        }

        let existing = SplitLayoutSizing.settingWeight(1, in: self)
        let inserted = SplitLayoutTree.split(
            axis: insertionAxis,
            weight: weightInParent,
            children: side.insertsBeforeTarget
                ? [incoming, existing]
                : [existing, incoming]
        )
        return SplitLayoutReconciler.canonicalizedForTiles(inserted)
            ?? SplitLayoutSizing.normalizingSiblingWeights(in: inserted)
    }

    private func insertingUnchecked(
        _ member: SplitMember,
        relativeTo targetMemberID: SplitMemberID,
        axis insertionAxis: SplitAxis,
        before: Bool,
        equalizeInsertedAxis: Bool
    ) -> SplitLayoutTree {
        switch self {
        case .leaf(let existingMember, let weight):
            guard existingMember.memberID == targetMemberID else { return self }
            let existing = SplitLayoutTree.leaf(
                member: existingMember,
                weight: 0.5
            )
            let incoming = SplitLayoutTree.leaf(member: member, weight: 0.5)
            return .split(
                axis: insertionAxis,
                weight: weight,
                children: before ? [incoming, existing] : [existing, incoming]
            )

        case .split(let axis, let weight, let children):
            if axis == insertionAxis,
               let targetIndex = children.firstIndex(where: {
                   $0.contains(targetMemberID) && $0.leafCount == 1
               }) {
                var updated = children
                let insertionIndex = before ? targetIndex : targetIndex + 1
                updated.insert(
                    .leaf(member: member, weight: 1),
                    at: insertionIndex
                )
                let split = SplitLayoutTree.split(
                    axis: axis,
                    weight: weight,
                    children: updated
                )
                return equalizeInsertedAxis
                    ? SplitLayoutSizing.equalizingImmediateChildWeights(in: split)
                    : split
            }

            return .split(
                axis: axis,
                weight: weight,
                children: children.map {
                    $0.contains(targetMemberID)
                        ? $0.insertingUnchecked(
                            member,
                            relativeTo: targetMemberID,
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

extension SplitLayoutTree: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .leaf:
            self = .leaf(
                member: try container.decode(SplitMember.self, forKey: .member),
                weight: try container.decode(Double.self, forKey: .weight)
            )
        case .split:
            self = .split(
                axis: try container.decode(SplitAxis.self, forKey: .axis),
                weight: try container.decode(Double.self, forKey: .weight),
                children: try container.decode(
                    [SplitLayoutTree].self,
                    forKey: .children
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let member, let weight):
            try container.encode(Kind.leaf, forKey: .kind)
            try container.encode(member, forKey: .member)
            try container.encode(weight, forKey: .weight)
        case .split(let axis, let weight, let children):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(axis, forKey: .axis)
            try container.encode(weight, forKey: .weight)
            try container.encode(children, forKey: .children)
        }
    }
}
