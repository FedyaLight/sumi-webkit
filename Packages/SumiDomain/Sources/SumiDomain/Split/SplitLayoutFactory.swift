import Foundation

public enum SplitLayoutFactory {
    public static func make(
        kind: SplitLayoutKind,
        members: [SplitMember]
    ) -> SplitLayoutTree? {
        guard isValidMemberSequence(members) else { return nil }
        switch kind {
        case .vertical:
            return equalSplitUnchecked(axis: .row, members: members)
        case .horizontal:
            return equalSplitUnchecked(axis: .column, members: members)
        case .grid:
            return grid(members: members)
        }
    }

    public static func equalSplit(
        axis: SplitAxis,
        members: [SplitMember]
    ) -> SplitLayoutTree? {
        guard isValidMemberSequence(members) else { return nil }
        return equalSplitUnchecked(axis: axis, members: members)
    }

    private static func equalSplitUnchecked(
        axis: SplitAxis,
        members: [SplitMember]
    ) -> SplitLayoutTree {
        let weight = 1 / Double(members.count)
        return .split(
            axis: axis,
            weight: 1,
            children: members.map { .leaf(member: $0, weight: weight) }
        )
    }

    private static func grid(members: [SplitMember]) -> SplitLayoutTree {
        if members.count <= 2 {
            return equalSplitUnchecked(axis: .row, members: members)
        }

        var columns: [SplitLayoutTree] = []
        var cursor = 0
        while cursor < members.count {
            let remaining = members.count - cursor
            let take = remaining == 3 ? 1 : min(2, remaining)
            let columnMembers = Array(members[cursor..<cursor + take])
            let column = take == 1
                ? SplitLayoutTree.leaf(member: columnMembers[0], weight: 1)
                : equalSplitUnchecked(axis: .column, members: columnMembers)
            columns.append(SplitLayoutSizing.settingWeight(1, in: column))
            cursor += take
        }
        return SplitLayoutSizing.normalizingSiblingWeights(
            in: .split(axis: .row, weight: 1, children: columns)
        )
    }

    private static func isValidMemberSequence(
        _ members: [SplitMember]
    ) -> Bool {
        guard !members.isEmpty,
              members.count <= SplitGroup.maximumMembers else {
            return false
        }
        return Set(members.map(\.memberID)).count == members.count
    }
}
