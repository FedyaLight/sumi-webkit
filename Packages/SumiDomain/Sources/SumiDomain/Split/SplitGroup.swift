import Foundation

/// Durable split structure shared by every window.
///
/// Active member and shortcut live-tab identities are deliberately absent:
/// both are window-local presentation state.
public struct SplitGroup: Identifiable, Equatable, Hashable, Sendable {
    public static let minimumMembers = 2
    public static let maximumMembers = 4

    public let id: UUID
    public let layoutKind: SplitLayoutKind
    public let layoutTree: SplitLayoutTree
    public let container: SplitGroupContainer

    private enum CodingKeys: String, CodingKey {
        case id
        case layoutKind
        case layoutTree
        case container
    }

    public init?(
        id: UUID = UUID(),
        layoutKind: SplitLayoutKind,
        layoutTree: SplitLayoutTree,
        container: SplitGroupContainer = .regularTabs(spaceId: nil)
    ) {
        let rootedTree = SplitLayoutSizing.settingWeight(1, in: layoutTree)
        guard let canonicalTree = SplitLayoutReconciler
            .canonicalizedForTiles(rootedTree) else {
            return nil
        }
        let memberIDs = canonicalTree.memberIDs
        guard memberIDs.count >= Self.minimumMembers,
              memberIDs.count <= Self.maximumMembers,
              Set(memberIDs).count == memberIDs.count else {
            return nil
        }
        if container.isShortcutSidebar {
            guard memberIDs.allSatisfy({ memberID in
                if case .shortcutPin = memberID { return true }
                return false
            }) else {
                return nil
            }
        }
        self.id = id
        self.layoutKind = layoutKind
        self.layoutTree = canonicalTree
        self.container = container
    }

    public static func make(
        id: UUID = UUID(),
        members: [SplitMember],
        layoutKind: SplitLayoutKind,
        container: SplitGroupContainer = .regularTabs(spaceId: nil)
    ) -> SplitGroup? {
        guard members.count >= minimumMembers,
              let tree = SplitLayoutFactory.make(
                  kind: layoutKind,
                  members: members
              ) else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            container: container
        )
    }

    public var members: [SplitMember] {
        layoutTree.members
    }

    public var memberIDs: [SplitMemberID] {
        layoutTree.memberIDs
    }

    public func contains(_ memberID: SplitMemberID) -> Bool {
        layoutTree.contains(memberID)
    }

    public func member(for memberID: SplitMemberID) -> SplitMember? {
        layoutTree.member(for: memberID)
    }

    public func changingLayout(to layoutKind: SplitLayoutKind) -> SplitGroup? {
        guard let tree = SplitLayoutFactory.make(
            kind: layoutKind,
            members: members
        ) else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            container: container
        )
    }

    public func replacingLayoutTree(
        with layoutTree: SplitLayoutTree
    ) -> SplitGroup? {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            container: container
        )
    }

    public func changingContainer(
        to container: SplitGroupContainer
    ) -> SplitGroup? {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            container: container
        )
    }

    public func removingMember(
        _ memberID: SplitMemberID
    ) -> SplitGroup? {
        guard let tree = layoutTree.removing(memberID: memberID) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func replacingMember(
        _ memberID: SplitMemberID,
        with replacement: SplitMember
    ) -> SplitGroup? {
        guard let tree = layoutTree.replacingMember(
            memberID,
            with: replacement
        ) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func swappingMembers(
        _ firstMemberID: SplitMemberID,
        _ secondMemberID: SplitMemberID
    ) -> SplitGroup? {
        guard let tree = layoutTree.swappingMembers(
            firstMemberID,
            secondMemberID
        ) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func movingMember(
        _ memberID: SplitMemberID,
        relativeTo targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard let tree = layoutTree.movingMember(
            memberID,
            relativeTo: targetMemberID,
            side: side
        ) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func movingMemberToRootEdge(
        _ memberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard let tree = layoutTree.movingMemberToRootEdge(
            memberID,
            side: side
        ) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func inserting(
        _ member: SplitMember,
        relativeTo targetMemberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard let tree = layoutTree.inserting(
            member,
            relativeTo: targetMemberID,
            side: side
        ) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    public func insertingAtRoot(
        _ member: SplitMember,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard let tree = layoutTree.insertingAtRoot(member, side: side) else {
            return nil
        }
        return replacingLayoutTree(with: tree)
    }

    /// Keeps the first valid group and rejects later duplicate group or member
    /// identities, yielding a deterministic persistence repair.
    public static func sanitized(_ groups: [SplitGroup]) -> [SplitGroup] {
        var usedGroupIDs = Set<UUID>()
        var usedMemberIDs = Set<SplitMemberID>()
        var result: [SplitGroup] = []
        result.reserveCapacity(groups.count)

        for group in groups {
            guard usedGroupIDs.insert(group.id).inserted else { continue }
            let memberIDs = Set(group.memberIDs)
            guard memberIDs.isDisjoint(with: usedMemberIDs) else { continue }
            usedMemberIDs.formUnion(memberIDs)
            result.append(group)
        }
        return result
    }
}

extension SplitGroup: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let layoutKind = try container.decode(
            SplitLayoutKind.self,
            forKey: .layoutKind
        )
        let layoutTree = try container.decode(
            SplitLayoutTree.self,
            forKey: .layoutTree
        )
        let groupContainer = try container.decode(
            SplitGroupContainer.self,
            forKey: .container
        )
        guard let group = SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            container: groupContainer
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .layoutTree,
                in: container,
                debugDescription: "A split group must contain two to four unique durable members in a canonical layout."
            )
        }
        self = group
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layoutKind, forKey: .layoutKind)
        try container.encode(layoutTree, forKey: .layoutTree)
        try container.encode(self.container, forKey: .container)
    }
}
