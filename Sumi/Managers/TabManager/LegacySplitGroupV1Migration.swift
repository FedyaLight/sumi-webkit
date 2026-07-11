import Foundation
import SumiDomain

/// Decode-only wire model for split groups written before durable member
/// identity became typed. Keep this shape exact: it is not a runtime model and
/// must never be encoded again.
indirect enum LegacySplitLayoutTreeV1: Decodable {
    case leaf(tabId: UUID, size: Double)
    case split(
        axis: LegacySplitAxisV1,
        size: Double,
        children: [LegacySplitLayoutTreeV1]
    )
}

enum LegacySplitAxisV1: String, Decodable {
    case row
    case column

    var domainValue: SumiDomain.SplitAxis {
        switch self {
        case .row:
            return .row
        case .column:
            return .column
        }
    }
}

enum LegacySplitLayoutKindV1: String, Decodable {
    case grid
    case vertical
    case horizontal

    var domainValue: SumiDomain.SplitLayoutKind {
        switch self {
        case .grid:
            return .grid
        case .vertical:
            return .vertical
        case .horizontal:
            return .horizontal
        }
    }
}

enum LegacySplitGroupHostV1 {
    case regular(spaceId: UUID?)
    case shortcutPinned(
        spaceId: UUID,
        profileId: UUID?,
        index: Int?
    )
}

extension LegacySplitGroupHostV1: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case index
    }

    private enum Kind: String, Decodable {
        case regular
        case shortcutPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .regular:
            self = .regular(
                spaceId: try container.decodeIfPresent(
                    UUID.self,
                    forKey: .spaceId
                )
            )
        case .shortcutPinned:
            self = .shortcutPinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                profileId: try container.decodeIfPresent(
                    UUID.self,
                    forKey: .profileId
                ),
                index: try container.decodeIfPresent(
                    Int.self,
                    forKey: .index
                )
            )
        }
    }
}

enum LegacySplitMemberOriginV1 {
    case regular(spaceId: UUID?, index: Int?)
    case essential(profileId: UUID?, index: Int)
    case spacePinned(spaceId: UUID, folderId: UUID?, index: Int)
    case generatedSpacePinnedFromRegular(spaceId: UUID, index: Int)
}

extension LegacySplitMemberOriginV1: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case folderId
        case index
    }

    private enum Kind: String, Decodable {
        case regular
        case essential
        case spacePinned
        case generatedSpacePinnedFromRegular
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .regular:
            self = .regular(
                spaceId: try container.decodeIfPresent(
                    UUID.self,
                    forKey: .spaceId
                ),
                index: try container.decodeIfPresent(
                    Int.self,
                    forKey: .index
                )
            )
        case .essential:
            self = .essential(
                profileId: try container.decodeIfPresent(
                    UUID.self,
                    forKey: .profileId
                ),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .spacePinned:
            self = .spacePinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                folderId: try container.decodeIfPresent(
                    UUID.self,
                    forKey: .folderId
                ),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .generatedSpacePinnedFromRegular:
            self = .generatedSpacePinnedFromRegular(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                index: try container.decode(Int.self, forKey: .index)
            )
        }
    }
}

struct LegacySplitGroupMemberV1: Decodable {
    let tabId: UUID
    let pinId: UUID?
    let origin: LegacySplitMemberOriginV1
}

struct LegacySplitGroupV1 {
    let id: UUID
    let layoutKind: LegacySplitLayoutKindV1
    let layoutTree: LegacySplitLayoutTreeV1
    let activeTabId: UUID?
    let host: LegacySplitGroupHostV1
    let members: [LegacySplitGroupMemberV1]
}

extension LegacySplitGroupV1: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case layoutKind
        case layoutTree
        case activeTabId
        case host
        case members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layoutKind = try container.decode(
            LegacySplitLayoutKindV1.self,
            forKey: .layoutKind
        )
        layoutTree = try container.decode(
            LegacySplitLayoutTreeV1.self,
            forKey: .layoutTree
        )
        activeTabId = try container.decodeIfPresent(
            UUID.self,
            forKey: .activeTabId
        )
        host = try container.decodeIfPresent(
            LegacySplitGroupHostV1.self,
            forKey: .host
        ) ?? .regular(spaceId: nil)
        members = try container.decodeIfPresent(
            [LegacySplitGroupMemberV1].self,
            forKey: .members
        ) ?? []
    }
}

enum LegacySplitGroupV1RepairReason {
    static let migratedArchive = "migrated legacy split group archive"
    static let discardedGlobalActiveMember =
        "discarded legacy global split active member"
    static let reboundLiveShortcut =
        "rebound legacy live split member to shortcut pin"
    static let repairedShortcutPlacement =
        "repaired legacy split shortcut return placement"
    static let ignoredStaleShortcutMetadata =
        "ignored stale legacy split shortcut metadata"
    static let removedUnknownMember =
        "removed unknown legacy split member"
    static let removedDuplicateMember =
        "removed duplicate legacy split member"
    static let collapsedLayout = "collapsed legacy split layout"
    static let discardedAmbiguousFolder =
        "discarded ambiguous legacy split folder placement"
    static let removedInvalidGroup = "removed invalid legacy split group"
    static let removedOverlappingGroup =
        "removed overlapping legacy split group"
}

/// Converts the old mixed live/durable identity graph into canonical domain
/// groups. Resolution uses disjoint regular-tab and shortcut-pin catalogs; an
/// unknown leaf is removed instead of being guessed from UUID shape.
struct LegacySplitGroupV1Migrator {
    let regularTabIDs: Set<UUID>
    let shortcutReturnPlacementsByPinID: [
        UUID: SumiDomain.SplitShortcutReturnPlacement
    ]

    func migrate(
        _ legacyGroups: [LegacySplitGroupV1],
        repairReasons: inout Set<String>
    ) -> [SumiDomain.SplitGroup] {
        guard legacyGroups.isEmpty == false else { return [] }
        repairReasons.insert(LegacySplitGroupV1RepairReason.migratedArchive)

        var migratedGroups: [SumiDomain.SplitGroup] = []
        var usedGroupIDs = Set<UUID>()
        var usedMemberIDs = Set<SumiDomain.SplitMemberID>()

        for legacyGroup in legacyGroups {
            var groupReasons = Set<String>()
            guard let migratedGroup = migrate(
                legacyGroup,
                repairReasons: &groupReasons
            ) else {
                groupReasons.insert(
                    LegacySplitGroupV1RepairReason.removedInvalidGroup
                )
                repairReasons.formUnion(groupReasons)
                continue
            }

            let memberIDs = Set(migratedGroup.memberIDs)
            guard usedGroupIDs.insert(migratedGroup.id).inserted,
                  memberIDs.isDisjoint(with: usedMemberIDs) else {
                repairReasons.insert(
                    LegacySplitGroupV1RepairReason.removedOverlappingGroup
                )
                repairReasons.formUnion(groupReasons)
                continue
            }

            usedMemberIDs.formUnion(memberIDs)
            migratedGroups.append(migratedGroup)
            repairReasons.formUnion(groupReasons)
        }

        return migratedGroups
    }

    private func migrate(
        _ legacyGroup: LegacySplitGroupV1,
        repairReasons: inout Set<String>
    ) -> SumiDomain.SplitGroup? {
        if legacyGroup.activeTabId != nil {
            repairReasons.insert(
                LegacySplitGroupV1RepairReason.discardedGlobalActiveMember
            )
        }

        var seenMemberIDs = Set<SumiDomain.SplitMemberID>()
        guard let layoutTree = migrate(
            legacyGroup.layoutTree,
            legacyMembers: legacyGroup.members,
            seenMemberIDs: &seenMemberIDs,
            repairReasons: &repairReasons
        ) else {
            return nil
        }

        let container = migrateContainer(
            legacyGroup.host,
            migratedTree: layoutTree,
            repairReasons: &repairReasons
        )
        return SumiDomain.SplitGroup(
            id: legacyGroup.id,
            layoutKind: legacyGroup.layoutKind.domainValue,
            layoutTree: layoutTree,
            container: container
        )
    }

    private func migrate(
        _ legacyTree: LegacySplitLayoutTreeV1,
        legacyMembers: [LegacySplitGroupMemberV1],
        seenMemberIDs: inout Set<SumiDomain.SplitMemberID>,
        repairReasons: inout Set<String>
    ) -> SumiDomain.SplitLayoutTree? {
        switch legacyTree {
        case .leaf(let legacyTabID, let size):
            guard let member = migrateMember(
                leafID: legacyTabID,
                legacyMembers: legacyMembers,
                repairReasons: &repairReasons
            ) else {
                repairReasons.insert(
                    LegacySplitGroupV1RepairReason.removedUnknownMember
                )
                return nil
            }
            guard seenMemberIDs.insert(member.memberID).inserted else {
                repairReasons.insert(
                    LegacySplitGroupV1RepairReason.removedDuplicateMember
                )
                return nil
            }
            return .leaf(member: member, weight: size)

        case .split(let axis, let size, let children):
            let migratedChildren = children.compactMap { child in
                migrate(
                    child,
                    legacyMembers: legacyMembers,
                    seenMemberIDs: &seenMemberIDs,
                    repairReasons: &repairReasons
                )
            }
            guard let first = migratedChildren.first else { return nil }
            guard migratedChildren.count > 1 else {
                repairReasons.insert(
                    LegacySplitGroupV1RepairReason.collapsedLayout
                )
                return settingWeight(size, in: first)
            }
            return .split(
                axis: axis.domainValue,
                weight: size,
                children: migratedChildren
            )
        }
    }

    private func migrateMember(
        leafID: UUID,
        legacyMembers: [LegacySplitGroupMemberV1],
        repairReasons: inout Set<String>
    ) -> SumiDomain.SplitMember? {
        let legacyMember = legacyMembers.first {
            $0.tabId == leafID || $0.pinId == leafID
        }

        if let pinID = legacyMember?.pinId {
            if let catalogPlacement =
                shortcutReturnPlacementsByPinID[pinID] {
                if leafID != pinID {
                    repairReasons.insert(
                        LegacySplitGroupV1RepairReason.reboundLiveShortcut
                    )
                }
                return .shortcutPin(
                    pinID,
                    returnPlacement: resolvedReturnPlacement(
                        legacyMember?.origin,
                        catalogPlacement: catalogPlacement,
                        repairReasons: &repairReasons
                    )
                )
            }
            repairReasons.insert(
                LegacySplitGroupV1RepairReason
                    .ignoredStaleShortcutMetadata
            )
            if regularTabIDs.contains(leafID) {
                return .regularTab(leafID)
            }
            if let leafPlacement =
                shortcutReturnPlacementsByPinID[leafID] {
                return .shortcutPin(
                    leafID,
                    returnPlacement: resolvedReturnPlacement(
                    legacyMember?.origin,
                    catalogPlacement: leafPlacement,
                    repairReasons: &repairReasons
                )
                )
            }
            return nil
        }

        let isRegularTab = regularTabIDs.contains(leafID)
        let catalogShortcutPlacement =
            shortcutReturnPlacementsByPinID[leafID]
        if isRegularTab { return .regularTab(leafID) }
        if let catalogShortcutPlacement {
            return .shortcutPin(
                leafID,
                returnPlacement: resolvedReturnPlacement(
                    legacyMember?.origin,
                    catalogPlacement: catalogShortcutPlacement,
                    repairReasons: &repairReasons
                )
            )
        }
        return nil
    }

    private func resolvedReturnPlacement(
        _ legacyOrigin: LegacySplitMemberOriginV1?,
        catalogPlacement: SumiDomain.SplitShortcutReturnPlacement,
        repairReasons: inout Set<String>
    ) -> SumiDomain.SplitShortcutReturnPlacement {
        guard let legacyOrigin,
              let migrated = compatibleReturnPlacement(
                  legacyOrigin,
                  catalogPlacement: catalogPlacement
              ) else {
            repairReasons.insert(
                LegacySplitGroupV1RepairReason.repairedShortcutPlacement
            )
            return catalogPlacement
        }
        return migrated
    }

    private func compatibleReturnPlacement(
        _ legacyOrigin: LegacySplitMemberOriginV1,
        catalogPlacement: SumiDomain.SplitShortcutReturnPlacement
    ) -> SumiDomain.SplitShortcutReturnPlacement? {
        switch (legacyOrigin, catalogPlacement) {
        case (
            .essential(let profileID, let index),
            .essential(let catalogProfileID, _)
        ) where profileID == catalogProfileID:
            return .essential(profileId: profileID, index: index)

        case (
            .spacePinned(let spaceID, let folderID, let index),
            .spacePinned(
                let catalogSpaceID,
                let catalogFolderID,
                _
            )
        ) where spaceID == catalogSpaceID
            && folderID == catalogFolderID:
            return .spacePinned(
                spaceId: spaceID,
                folderId: folderID,
                index: index
            )

        case (
            .generatedSpacePinnedFromRegular(let spaceID, let index),
            .spacePinned(let catalogSpaceID, _, _)
        ) where spaceID == catalogSpaceID:
            return .generatedSpacePinnedFromRegular(
                spaceId: spaceID,
                index: index
            )

        default:
            return nil
        }
    }

    private func migrateContainer(
        _ host: LegacySplitGroupHostV1,
        migratedTree: SumiDomain.SplitLayoutTree,
        repairReasons: inout Set<String>
    ) -> SumiDomain.SplitGroupContainer {
        switch host {
        case .regular(let spaceID):
            return .regularTabs(spaceId: spaceID)

        case .shortcutPinned(
            let spaceID,
            let profileID,
            let index
        ):
            let folderResolution = consistentFolderID(
                for: migratedTree,
                hostSpaceID: spaceID
            )
            if folderResolution.discardedAmbiguousFolder {
                repairReasons.insert(
                    LegacySplitGroupV1RepairReason
                        .discardedAmbiguousFolder
                )
            }
            return .shortcutSidebar(
                spaceId: spaceID,
                profileId: profileID,
                folderId: folderResolution.folderID,
                index: index
            )
        }
    }

    private func consistentFolderID(
        for tree: SumiDomain.SplitLayoutTree,
        hostSpaceID: UUID
    ) -> (folderID: UUID?, discardedAmbiguousFolder: Bool) {
        let shortcutPinIDs = tree.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        }
        guard shortcutPinIDs.isEmpty == false else {
            return (nil, false)
        }

        var folderIDs: [UUID] = []
        var everyShortcutHasValidFolder = true
        for pinID in shortcutPinIDs {
            if case .spacePinned(
                let spaceID,
                let folderID,
                _
            )? = shortcutReturnPlacementsByPinID[pinID],
            spaceID == hostSpaceID,
            let folderID {
                folderIDs.append(folderID)
            } else {
                everyShortcutHasValidFolder = false
            }
        }

        if everyShortcutHasValidFolder,
           let folderID = folderIDs.first,
           folderIDs.allSatisfy({ $0 == folderID }) {
            return (folderID, false)
        }
        let hasFolderEvidence = tree.members.contains { member in
            guard case .spacePinned(_, let folderID, _)? =
                member.returnPlacement else { return false }
            return folderID != nil
        }
        return (nil, hasFolderEvidence || !folderIDs.isEmpty)
    }

    private func settingWeight(
        _ weight: Double,
        in tree: SumiDomain.SplitLayoutTree
    ) -> SumiDomain.SplitLayoutTree {
        switch tree {
        case .leaf(let member, _):
            return .leaf(member: member, weight: weight)
        case .split(let axis, _, let children):
            return .split(
                axis: axis,
                weight: weight,
                children: children
            )
        }
    }
}
