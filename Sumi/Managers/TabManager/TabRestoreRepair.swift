import Foundation

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
        _ folders: [TabSnapshotRepository.SnapshotFolder],
        repairReasons: inout Set<String>
    ) -> [TabSnapshotRepository.SnapshotFolder] {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        func hasCycle(from folder: TabSnapshotRepository.SnapshotFolder) -> Bool {
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
                return TabSnapshotRepository.SnapshotFolder(
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

    /// Decodes persisted split groups, repairs shortcut-backed member bindings, drops groups
    /// that no longer meet the minimum-tab requirement, and sanitizes overlaps.
    static func restoreSplitGroups(
        from data: Data?,
        validTabIds: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> [SplitGroup] {
        guard let data, data.isEmpty == false else { return [] }
        do {
            let decoded = try JSONDecoder().decode([SplitGroup].self, from: data)
            let restored = decoded.compactMap { group -> SplitGroup? in
                let repairedGroup = repairShortcutBackedSplitGroup(
                    group,
                    validTabIds: validTabIds,
                    repairReasons: &repairReasons
                )
                let tabIds = repairedGroup.tabIds.filter { validTabIds.contains($0) }
                guard tabIds.count >= SplitGroup.minimumTabs else {
                    repairReasons.insert("removed stale split group")
                    return nil
                }
                if tabIds != repairedGroup.tabIds {
                    repairReasons.insert("repaired stale split group tabs")
                    return SplitGroup.make(
                        tabIds: tabIds,
                        layoutKind: repairedGroup.layoutKind,
                        activeTabId: repairedGroup.activeTabId.flatMap { tabIds.contains($0) ? $0 : tabIds.first },
                        host: repairedGroup.host,
                        members: repairedGroup.members
                    )
                }
                return repairedGroup
            }
            let sanitized = SplitGroup.sanitized(restored)
            if sanitized.count != restored.count {
                repairReasons.insert("removed overlapping split groups")
            }
            return sanitized
        } catch {
            repairReasons.insert("removed unreadable split groups")
            return []
        }
    }

    /// Rebinds a split-group member whose live tab id is gone to its backing shortcut pin id
    /// when that pin is still valid, so a shortcut-hosted split survives a live-tab teardown.
    static func repairShortcutBackedSplitGroup(
        _ group: SplitGroup,
        validTabIds: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> SplitGroup {
        var repaired = group
        for tabId in group.tabIds where !validTabIds.contains(tabId) {
            guard let member = repaired.member(for: tabId),
                  let pinId = member.pinId,
                  validTabIds.contains(pinId)
            else {
                continue
            }
            repairReasons.insert("repaired split group shortcut binding")
            repaired = repaired.replacingMemberTab(tabId, with: pinId)
        }
        return repaired
    }
}
