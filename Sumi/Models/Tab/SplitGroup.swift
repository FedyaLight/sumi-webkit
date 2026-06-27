import CoreGraphics
import Foundation

enum SplitAxis: String, Codable, Hashable, Sendable {
    case row
    case column
}

enum SplitLayoutKind: String, Codable, CaseIterable, Hashable, Sendable {
    case grid
    case vertical
    case horizontal

    var primaryAxis: SplitAxis {
        switch self {
        case .grid, .vertical:
            return .row
        case .horizontal:
            return .column
        }
    }
}

enum SplitDropSide: String, Codable, Hashable, Sendable {
    case left
    case right
    case top
    case bottom
    case center

    var insertionAxis: SplitAxis? {
        switch self {
        case .left, .right:
            return .row
        case .top, .bottom:
            return .column
        case .center:
            return nil
        }
    }
}

enum SplitDropTargetScope: String, Codable, Hashable, Sendable {
    case pane
    case plane
    case group
}

enum SplitDropPreviewStyle: String, Codable, Hashable, Sendable {
    case edge
    case center
}

enum SplitDropTargetIntent: String, Codable, Hashable, Sendable {
    case firstSplit
    case rootEdge
    case planeEdge
    case siblingEdge
    case flatThreePair
    case flatFourPair
    case flatFourReorder
    case mixedThreeOnePair
    case fullGroupPanePair
    case paneCenter
}

enum SplitGroupHost: Codable, Equatable, Hashable, Sendable {
    case regular(spaceId: UUID?)
    case shortcutPinned(spaceId: UUID, profileId: UUID?, index: Int?)

    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case index
    }

    private enum Kind: String, Codable {
        case regular
        case shortcutPinned
    }

    var isShortcutPinned: Bool {
        if case .shortcutPinned = self { return true }
        return false
    }

    var spaceId: UUID? {
        switch self {
        case .regular(let spaceId):
            return spaceId
        case .shortcutPinned(let spaceId, _, _):
            return spaceId
        }
    }

    var shortcutPinnedIndex: Int? {
        guard case .shortcutPinned(_, _, let index) = self else { return nil }
        return index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .regular:
            self = .regular(spaceId: try container.decodeIfPresent(UUID.self, forKey: .spaceId))
        case .shortcutPinned:
            self = .shortcutPinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regular(let spaceId):
            try container.encode(Kind.regular, forKey: .kind)
            try container.encodeIfPresent(spaceId, forKey: .spaceId)
        case .shortcutPinned(let spaceId, let profileId, let index):
            try container.encode(Kind.shortcutPinned, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encodeIfPresent(index, forKey: .index)
        }
    }

    func settingShortcutPinnedIndex(_ index: Int?) -> SplitGroupHost {
        switch self {
        case .regular:
            return self
        case .shortcutPinned(let spaceId, let profileId, _):
            return .shortcutPinned(spaceId: spaceId, profileId: profileId, index: index)
        }
    }
}

enum SplitGroupMemberOrigin: Codable, Equatable, Hashable, Sendable {
    case regular(spaceId: UUID?, index: Int?)
    case essential(profileId: UUID?, index: Int)
    case spacePinned(spaceId: UUID, folderId: UUID?, index: Int)
    case generatedSpacePinnedFromRegular(spaceId: UUID, index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case folderId
        case index
    }

    private enum Kind: String, Codable {
        case regular
        case essential
        case spacePinned
        case generatedSpacePinnedFromRegular
    }

    var isShortcutBacked: Bool {
        switch self {
        case .regular:
            return false
        case .essential, .spacePinned, .generatedSpacePinnedFromRegular:
            return true
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .regular:
            self = .regular(
                spaceId: try container.decodeIfPresent(UUID.self, forKey: .spaceId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .essential:
            self = .essential(
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .spacePinned:
            self = .spacePinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                folderId: try container.decodeIfPresent(UUID.self, forKey: .folderId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .generatedSpacePinnedFromRegular:
            self = .generatedSpacePinnedFromRegular(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                index: try container.decode(Int.self, forKey: .index)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regular(let spaceId, let index):
            try container.encode(Kind.regular, forKey: .kind)
            try container.encodeIfPresent(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(index, forKey: .index)
        case .essential(let profileId, let index):
            try container.encode(Kind.essential, forKey: .kind)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encode(index, forKey: .index)
        case .spacePinned(let spaceId, let folderId, let index):
            try container.encode(Kind.spacePinned, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(folderId, forKey: .folderId)
            try container.encode(index, forKey: .index)
        case .generatedSpacePinnedFromRegular(let spaceId, let index):
            try container.encode(Kind.generatedSpacePinnedFromRegular, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encode(index, forKey: .index)
        }
    }
}

struct SplitGroupMember: Codable, Equatable, Hashable, Sendable {
    var tabId: UUID
    var pinId: UUID?
    var origin: SplitGroupMemberOrigin

    var stableId: UUID {
        pinId ?? tabId
    }

    var isShortcutBacked: Bool {
        pinId != nil || origin.isShortcutBacked
    }
}

struct SplitDropTarget: Equatable {
    let tabId: UUID
    let side: SplitDropSide
    let targetRect: CGRect
    let scope: SplitDropTargetScope
    let previewStyle: SplitDropPreviewStyle
    let planePath: [Int]
    let intent: SplitDropTargetIntent
    let resolvedLayoutTree: SplitLayoutTree?

    init(
        tabId: UUID,
        side: SplitDropSide,
        targetRect: CGRect,
        scope: SplitDropTargetScope = .pane,
        previewStyle: SplitDropPreviewStyle = .edge,
        planePath: [Int] = [],
        intent: SplitDropTargetIntent? = nil,
        resolvedLayoutTree: SplitLayoutTree? = nil
    ) {
        self.tabId = tabId
        self.side = side
        self.targetRect = targetRect
        self.scope = scope
        self.previewStyle = previewStyle
        self.planePath = planePath
        self.intent = intent ?? {
            switch (scope, previewStyle) {
            case (_, .center):
                return .paneCenter
            case (.group, _):
                return .rootEdge
            case (.plane, _):
                return .planeEdge
            case (.pane, _):
                return .planeEdge
            }
        }()
        self.resolvedLayoutTree = resolvedLayoutTree
    }

    func resolving(
        targetRect: CGRect,
        resolvedLayoutTree: SplitLayoutTree
    ) -> SplitDropTarget {
        SplitDropTarget(
            tabId: tabId,
            side: side,
            targetRect: targetRect,
            scope: scope,
            previewStyle: previewStyle,
            planePath: planePath,
            intent: intent,
            resolvedLayoutTree: resolvedLayoutTree
        )
    }
}

struct SplitGroup: Identifiable, Codable, Equatable, Hashable, Sendable {
    static let maximumTabs = 4
    static let minimumTabs = 2

    var id: UUID
    var layoutKind: SplitLayoutKind
    var layoutTree: SplitLayoutTree
    var activeTabId: UUID?
    var host: SplitGroupHost
    var members: [SplitGroupMember]

    private enum CodingKeys: String, CodingKey {
        case id
        case layoutKind
        case layoutTree
        case activeTabId
        case host
        case members
    }

    init(
        id: UUID = UUID(),
        layoutKind: SplitLayoutKind,
        layoutTree: SplitLayoutTree,
        activeTabId: UUID? = nil,
        host: SplitGroupHost = .regular(spaceId: nil),
        members: [SplitGroupMember] = []
    ) {
        self.id = id
        self.layoutKind = layoutKind
        let normalizedTree = layoutTree.normalizingSiblingSizes()
        self.layoutTree = normalizedTree.canonicalizedForTiles() ?? normalizedTree
        self.activeTabId = activeTabId
        self.host = host
        self.members = Self.sanitizedMembers(members, validTabIds: Set(self.layoutTree.tabIds))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layoutKind = try container.decode(SplitLayoutKind.self, forKey: .layoutKind)
        let decodedTree = try container.decode(SplitLayoutTree.self, forKey: .layoutTree)
        let normalizedTree = decodedTree.normalizingSiblingSizes()
        layoutTree = normalizedTree.canonicalizedForTiles() ?? normalizedTree
        activeTabId = try container.decodeIfPresent(UUID.self, forKey: .activeTabId)
        host = try container.decodeIfPresent(SplitGroupHost.self, forKey: .host) ?? .regular(spaceId: nil)
        members = Self.sanitizedMembers(
            try container.decodeIfPresent([SplitGroupMember].self, forKey: .members) ?? [],
            validTabIds: Set(layoutTree.tabIds)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layoutKind, forKey: .layoutKind)
        try container.encode(layoutTree, forKey: .layoutTree)
        try container.encodeIfPresent(activeTabId, forKey: .activeTabId)
        try container.encode(host, forKey: .host)
        try container.encode(members, forKey: .members)
    }

    var tabIds: [UUID] {
        layoutTree.tabIds
    }

    var isShortcutHosted: Bool {
        host.isShortcutPinned
    }

    var hostSpaceId: UUID? {
        host.spaceId
    }

    var shortcutPinnedIndex: Int? {
        host.shortcutPinnedIndex
    }

    var shortcutPinIds: Set<UUID> {
        Set(members.compactMap(\.pinId))
    }

    func member(for tabId: UUID) -> SplitGroupMember? {
        members.first { $0.tabId == tabId || $0.pinId == tabId }
    }

    func member(forPinId pinId: UUID) -> SplitGroupMember? {
        members.first { $0.pinId == pinId }
    }

    func containsPin(_ pinId: UUID) -> Bool {
        members.contains { $0.pinId == pinId }
    }

    var isValid: Bool {
        let ids = tabIds
        return ids.count >= Self.minimumTabs
            && ids.count <= Self.maximumTabs
            && uniqueSplitTabIdsPreservingOrder(ids).count == ids.count
    }

    func contains(_ tabId: UUID) -> Bool {
        layoutTree.contains(tabId) || containsPin(tabId)
    }

    func settingLayoutKind(_ kind: SplitLayoutKind) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: kind,
            layoutTree: .make(kind: kind, tabIds: tabIds),
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func settingActiveTab(_ tabId: UUID?) -> SplitGroup {
        var copy = self
        copy.activeTabId = tabId.flatMap { contains($0) ? $0 : nil }
        return copy
    }

    func canonicalizedForTiles() -> SplitGroup? {
        guard let tree = layoutTree.canonicalizedForTiles() else { return nil }
        let resolvedActiveTabId = activeTabId.flatMap { tree.contains($0) ? $0 : nil } ?? tree.tabIds.first
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: resolvedActiveTabId,
            host: host,
            members: members
        )
    }

    func removing(tabId: UUID) -> SplitGroup? {
        guard let tree = layoutTree.removing(tabId: tabId) else { return nil }
        let remainingIds = tree.tabIds
        guard remainingIds.count >= Self.minimumTabs else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: activeTabId == tabId ? remainingIds.first : activeTabId,
            host: host,
            members: members.filter { $0.tabId != tabId && $0.pinId != tabId }
        )
    }

    func movingTab(_ tabId: UUID, relativeTo targetTabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center else {
            return swappingTabs(tabId, targetTabId)
        }
        guard let tree = layoutTree.movingTab(tabId, relativeTo: targetTabId, side: side) else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func movingTabToRootEdge(_ tabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center,
              contains(tabId),
              let tree = layoutTree.movingTabToRootEdge(tabId, side: side)
        else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func isMovingTabNoOpAtRootEdge(_ tabId: UUID, side: SplitDropSide) -> Bool {
        guard let moved = movingTabToRootEdge(tabId, side: side) else {
            return true
        }
        return moved.layoutTree.hasSameStructure(as: layoutTree)
    }

    func resolvingDrop(
        draggedTabId: UUID,
        target: SplitDropTarget,
        bounds: CGRect
    ) -> SplitResolvedDrop? {
        layoutTree.resolvingDrop(
            draggedTabId: draggedTabId,
            target: target,
            bounds: bounds
        )
    }

    func swappingTabs(_ firstTabId: UUID, _ secondTabId: UUID) -> SplitGroup? {
        guard contains(firstTabId), contains(secondTabId) else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.swappingTabs(firstTabId, secondTabId),
            activeTabId: firstTabId,
            host: host,
            members: members.map { member in
                if member.tabId == firstTabId {
                    var copy = member
                    copy.tabId = secondTabId
                    return copy
                }
                if member.tabId == secondTabId {
                    var copy = member
                    copy.tabId = firstTabId
                    return copy
                }
                return member
            }
        )
    }

    func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard tabIds.contains(tabId) == false else { return settingActiveTab(tabId) }
        guard tabIds.count < Self.maximumTabs else { return nil }
        let tree = layoutTree.inserting(tabId: tabId, relativeTo: targetTabId, side: side)
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func insertingAtRoot(tabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center else { return settingActiveTab(tabId) }
        guard tabIds.contains(tabId) == false else { return settingActiveTab(tabId) }
        guard tabIds.count < Self.maximumTabs else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.insertingAtRoot(tabId: tabId, side: side),
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func settingHost(_ host: SplitGroupHost) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func settingMembers(_ members: [SplitGroupMember]) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func upsertingMember(_ member: SplitGroupMember) -> SplitGroup {
        var updated = members.filter {
            $0.tabId != member.tabId
                && (member.pinId == nil || $0.pinId != member.pinId)
                && $0.stableId != member.stableId
        }
        updated.append(member)
        return settingMembers(updated)
    }

    func removingMember(tabId: UUID) -> SplitGroup {
        settingMembers(members.filter { $0.tabId != tabId && $0.pinId != tabId })
    }

    func replacingMemberTab(_ oldTabId: UUID, with newTabId: UUID) -> SplitGroup {
        let updatedMembers = members.map { member -> SplitGroupMember in
            guard member.tabId == oldTabId || member.pinId == oldTabId else { return member }
            var copy = member
            copy.tabId = newTabId
            return copy
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.replacingTab(oldTabId, with: newTabId),
            activeTabId: activeTabId == oldTabId ? newTabId : activeTabId,
            host: host,
            members: updatedMembers
        )
    }

    static func make(
        tabIds: [UUID],
        layoutKind: SplitLayoutKind,
        activeTabId: UUID? = nil,
        host: SplitGroupHost = .regular(spaceId: nil),
        members: [SplitGroupMember] = []
    ) -> SplitGroup? {
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(tabIds)
        guard uniqueIds.count >= minimumTabs, uniqueIds.count <= maximumTabs else { return nil }
        return SplitGroup(
            layoutKind: layoutKind,
            layoutTree: .make(kind: layoutKind, tabIds: uniqueIds),
            activeTabId: activeTabId ?? uniqueIds.last,
            host: host,
            members: members
        )
    }

    static func sanitized(_ groups: [SplitGroup]) -> [SplitGroup] {
        var usedGroupIds: Set<UUID> = []
        var usedMemberIds: Set<UUID> = []
        var result: [SplitGroup] = []
        for group in groups {
            guard let canonicalGroup = group.canonicalizedForTiles(),
                  canonicalGroup.isValid
            else {
                continue
            }
            guard usedGroupIds.insert(canonicalGroup.id).inserted else { continue }
            let ids = Set(canonicalGroup.tabIds).union(canonicalGroup.shortcutPinIds)
            guard ids.allSatisfy({ usedMemberIds.contains($0) == false }) else { continue }
            usedMemberIds.formUnion(ids)
            result.append(canonicalGroup)
        }
        return result
    }

    private static func sanitizedMembers(
        _ members: [SplitGroupMember],
        validTabIds: Set<UUID>
    ) -> [SplitGroupMember] {
        var seen = Set<UUID>()
        var result: [SplitGroupMember] = []
        for member in members {
            guard validTabIds.contains(member.tabId) || member.pinId.map(validTabIds.contains) == true else {
                continue
            }
            guard seen.insert(member.stableId).inserted else { continue }
            result.append(member)
        }
        return result
    }
}
