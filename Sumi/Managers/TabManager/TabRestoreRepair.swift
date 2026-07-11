import Foundation
import SumiDomain

/// Pure repair/sanitize policy for persisted tab data during startup restore, split out of
/// `TabRestoreLoader`. Given possibly-corrupt persisted structures it returns valid domain
/// objects and records human-readable reasons into `repairReasons` (used for diagnostics).
///
/// These functions are the "what is a safe repair" policy, deliberately free of the loader's
/// fetch/build *mechanism* (SwiftData reads, `Raw*` decoding, categorization). Keeping them
/// here isolates the repair rules and — because they are pure — lets them be unit-tested
/// directly, which matters for restore paths where a bad repair silently drops user data.
enum TabRestoreRepair {
    /// Detaches folders whose parent is missing, in a different space, self-referential, or
    /// part of a cycle, so the restored hierarchy is always a valid forest.
    static func repairedFolderHierarchy(
        _ folders: [TabPersistenceFolder],
        repairReasons: inout Set<String>
    ) -> [TabPersistenceFolder] {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        func hasCycle(from folder: TabPersistenceFolder) -> Bool {
            var seen: Set<UUID> = [folder.id]
            var parentId = folder.parentFolderId
            while let id = parentId {
                guard seen.insert(id).inserted else { return true }
                parentId = foldersById[id]?.parentFolderId
            }
            return false
        }

        return folders.map { folder in
            guard let parentId = folder.parentFolderId else { return folder }
            guard let parent = foldersById[parentId],
                  parent.spaceId == folder.spaceId,
                  !hasCycle(from: folder) else {
                repairReasons.insert("moved folder out of invalid parent")
                return TabPersistenceFolder(
                    id: folder.id,
                    name: folder.name,
                    icon: folder.icon,
                    color: folder.color,
                    spaceId: folder.spaceId,
                    parentFolderId: nil,
                    isOpen: folder.isOpen,
                    index: folder.index
                )
            }
            return folder
        }
    }

    /// Decodes the versioned durable split archive or migrates the exact
    /// decode-only v1 wire shape. Regular tabs and shortcut pins are separate
    /// catalogs so a stale runtime UUID can never be guessed into existence.
    static func restoreSplitGroups(
        from data: Data?,
        regularTabIDs: Set<UUID>,
        shortcutReturnPlacementsByPinID: [
            UUID: SumiDomain.SplitShortcutReturnPlacement
        ],
        repairReasons: inout Set<String>
    ) -> [SumiDomain.SplitGroup] {
        guard let data, data.isEmpty == false else { return [] }
        do {
            switch try TabPersistenceCodec().decodeSplitGroupArchive(
                from: data
            ) {
            case .version2(let groups, let discardedEntryCount):
                if discardedEntryCount > 0 {
                    repairReasons.insert(
                        "removed unreadable split group entry"
                    )
                }
                return repairVersion2SplitGroups(
                    groups,
                    regularTabIDs: regularTabIDs,
                    shortcutPinIDs: Set(
                        shortcutReturnPlacementsByPinID.keys
                    ),
                    repairReasons: &repairReasons
                )

            case .legacyVersion1(let groups):
                return LegacySplitGroupV1Migrator(
                    regularTabIDs: regularTabIDs,
                    shortcutReturnPlacementsByPinID:
                        shortcutReturnPlacementsByPinID
                ).migrate(
                    groups,
                    repairReasons: &repairReasons
                )
            }
        } catch {
            repairReasons.insert("removed unreadable split groups")
            return []
        }
    }

    private static func repairVersion2SplitGroups(
        _ groups: [SumiDomain.SplitGroup],
        regularTabIDs: Set<UUID>,
        shortcutPinIDs: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> [SumiDomain.SplitGroup] {
        let restored = groups.compactMap { group -> SumiDomain.SplitGroup? in
            var didRemoveMember = false
            var didCollapseLayout = false
            guard let tree = pruningStaleMembers(
                from: group.layoutTree,
                regularTabIDs: regularTabIDs,
                shortcutPinIDs: shortcutPinIDs,
                didRemoveMember: &didRemoveMember,
                didCollapseLayout: &didCollapseLayout
            ), let repairedGroup = SumiDomain.SplitGroup(
                id: group.id,
                layoutKind: group.layoutKind,
                layoutTree: tree,
                container: group.container
            ) else {
                repairReasons.insert("removed stale split group")
                return nil
            }

            if didRemoveMember {
                repairReasons.insert("removed stale split group member")
            }
            if didCollapseLayout {
                repairReasons.insert("collapsed stale split group layout")
            }
            return repairedGroup
        }

        let sanitized = SumiDomain.SplitGroup.sanitized(restored)
        if sanitized.count != restored.count {
            repairReasons.insert("removed overlapping split groups")
        }
        return sanitized
    }

    private static func pruningStaleMembers(
        from tree: SumiDomain.SplitLayoutTree,
        regularTabIDs: Set<UUID>,
        shortcutPinIDs: Set<UUID>,
        didRemoveMember: inout Bool,
        didCollapseLayout: inout Bool
    ) -> SumiDomain.SplitLayoutTree? {
        switch tree {
        case .leaf(let member, let weight):
            let exists: Bool
            switch member.memberID {
            case .regularTab(let tabID):
                exists = regularTabIDs.contains(tabID)
            case .shortcutPin(let pinID):
                exists = shortcutPinIDs.contains(pinID)
            }
            guard exists else {
                didRemoveMember = true
                return nil
            }
            return .leaf(member: member, weight: weight)

        case .split(let axis, let weight, let children):
            let kept = children.compactMap { child in
                pruningStaleMembers(
                    from: child,
                    regularTabIDs: regularTabIDs,
                    shortcutPinIDs: shortcutPinIDs,
                    didRemoveMember: &didRemoveMember,
                    didCollapseLayout: &didCollapseLayout
                )
            }
            guard let first = kept.first else { return nil }
            guard kept.count > 1 else {
                didCollapseLayout = true
                return settingWeight(weight, in: first)
            }
            return .split(
                axis: axis,
                weight: weight,
                children: kept
            )
        }
    }

    private static func settingWeight(
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
