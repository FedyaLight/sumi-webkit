import Foundation
import SumiDomain

struct TabRestoreSpacePlanner: Sendable {
    func makeSpaces(
        from records: [TabRestoreSpaceRecord],
        defaultProfileId: UUID?,
        blockedProfileIDs: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> [TabRestoreSpaceDTO] {
        var seenIds: Set<UUID> = []
        return records
            .sorted(by: isOrderedBefore)
            .compactMap { record in
                guard seenIds.insert(record.id).inserted else {
                    repairReasons.insert("removed duplicate space")
                    return nil
                }

                let workspaceTheme = WorkspaceTheme.decode(record.workspaceThemeData ?? Data())
                    ?? .default
                let storedProfileID = record.profileId.flatMap {
                    blockedProfileIDs.contains($0) ? nil : $0
                }
                let profileId = storedProfileID ?? defaultProfileId
                if record.profileId != nil, storedProfileID == nil {
                    repairReasons.insert("reassigned blocked space profile")
                } else if record.profileId == nil, defaultProfileId != nil {
                    repairReasons.insert("assigned default profile to space")
                }
                return TabRestoreSpaceDTO(
                    id: record.id,
                    name: record.name,
                    icon: record.icon,
                    workspaceTheme: workspaceTheme,
                    profileId: profileId
                )
            }
    }

    func makeDefaultSpace(profileId: UUID?) -> TabRestoreSpaceDTO {
        TabRestoreSpaceDTO(
            id: UUID(),
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            workspaceTheme: .default,
            profileId: profileId
        )
    }

    private func isOrderedBefore(
        _ lhs: TabRestoreSpaceRecord,
        _ rhs: TabRestoreSpaceRecord
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TabRestoreFolderPlanner: Sendable {
    func makeFoldersBySpace(
        from records: [TabRestoreFolderRecord],
        validSpaceIds: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> [UUID: [TabPersistenceFolder]] {
        var seenIds: Set<UUID> = []
        var foldersBySpace: [UUID: [TabPersistenceFolder]] = [:]

        for record in records.sorted(by: isOrderedBefore) {
            guard seenIds.insert(record.id).inserted else {
                repairReasons.insert("removed duplicate folder")
                continue
            }
            guard validSpaceIds.contains(record.spaceId) else {
                repairReasons.insert("removed folder with missing space")
                continue
            }

            let icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(record.icon)
            if icon != record.icon {
                repairReasons.insert("normalized folder icon")
            }
            foldersBySpace[record.spaceId, default: []].append(
                TabPersistenceFolder(
                    id: record.id,
                    name: record.name,
                    icon: icon,
                    color: record.color,
                    spaceId: record.spaceId,
                    parentFolderId: record.parentFolderId,
                    isOpen: record.isOpen,
                    index: record.index
                )
            )
        }

        for spaceId in foldersBySpace.keys {
            foldersBySpace[spaceId] = TabRestoreRepair.repairedFolderHierarchy(
                foldersBySpace[spaceId] ?? [],
                repairReasons: &repairReasons
            ).sorted(by: isOrderedBefore)
        }
        return foldersBySpace
    }

    private func isOrderedBefore(
        _ lhs: TabRestoreFolderRecord,
        _ rhs: TabRestoreFolderRecord
    ) -> Bool {
        if lhs.spaceId != rhs.spaceId {
            return lhs.spaceId.uuidString < rhs.spaceId.uuidString
        }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isOrderedBefore(
        _ lhs: TabPersistenceFolder,
        _ rhs: TabPersistenceFolder
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TabRestoreSelectionPlanner: Sendable {
    func resolve(
        states: [TabRestoreStateRecord],
        spaces: [TabRestoreSpaceDTO],
        regularTabsBySpace: [UUID: [TabRestoreTabDTO]],
        repairReasons: inout Set<String>
    ) -> TabPersistenceSelection {
        guard let firstSpace = spaces.first else {
            return TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        }
        if states.count > 1 {
            repairReasons.insert("removed duplicate tab state")
        }

        let state = states.first
        let validSpaceIds = Set(spaces.map(\.id))
        let currentSpaceId: UUID
        if let storedSpaceId = state?.currentSpaceID, validSpaceIds.contains(storedSpaceId) {
            currentSpaceId = storedSpaceId
        } else {
            currentSpaceId = firstSpace.id
            if state?.currentSpaceID != nil {
                repairReasons.insert("repaired stale selected space")
            }
        }

        let tabs = regularTabsBySpace[currentSpaceId] ?? []
        let currentTabId: UUID?
        if let storedTabId = state?.currentTabID,
           tabs.contains(where: { $0.id == storedTabId }) {
            currentTabId = storedTabId
        } else {
            currentTabId = tabs.first?.id
            if state?.currentTabID != nil {
                repairReasons.insert("repaired stale selected tab")
            }
        }
        return TabPersistenceSelection(
            currentTabID: currentTabId,
            currentSpaceID: currentSpaceId
        )
    }
}
