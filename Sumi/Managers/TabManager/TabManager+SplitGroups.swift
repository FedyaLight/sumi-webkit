import Foundation

@MainActor
extension TabManager {
    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        splitGroupIdByTabId[tabId].flatMap { splitGroupById[$0] }
    }

    func splitGroup(with id: UUID) -> SplitGroup? {
        splitGroupById[id]
    }

    func splitGroupIds(containing tabId: UUID) -> [UUID] {
        splitGroupIdByTabId[tabId].map { [$0] } ?? []
    }

    func visibleSplitTabIds(containing tabId: UUID?) -> [UUID] {
        guard let tabId, let group = splitGroup(containing: tabId) else { return [] }
        return group.tabIds
    }

    func upsertSplitGroup(_ group: SplitGroup, schedulePersistence shouldPersist: Bool = true) {
        guard let canonicalGroup = group.canonicalizedForTiles(),
              canonicalGroup.isValid
        else {
            return
        }
        let sanitized = canonicalGroup.settingActiveTab(canonicalGroup.activeTabId ?? canonicalGroup.tabIds.last)
        if let index = splitGroupIndexById[sanitized.id] {
            splitGroups[index] = sanitized
        } else {
            let memberIds = Set(sanitized.tabIds)
            splitGroups.removeAll { existing in
                existing.id != sanitized.id && existing.tabIds.contains { memberIds.contains($0) }
            }
            splitGroups.append(sanitized)
        }
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    func removeSplitGroup(id: UUID, schedulePersistence shouldPersist: Bool = true) {
        guard let index = splitGroupIndexById[id] else { return }
        splitGroups.remove(at: index)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    func removeSplitGroups(containing tabId: UUID, schedulePersistence shouldPersist: Bool = true) {
        let updated = splitGroups.compactMap { group in
            group.contains(tabId) ? group.removing(tabId: tabId) : group
        }
        guard updated != splitGroups else { return }
        splitGroups = updated
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    func replaceSplitGroups(_ groups: [SplitGroup], schedulePersistence shouldPersist: Bool = true) {
        let validGroups = SplitGroup.sanitized(groups)
        guard validGroups != splitGroups else { return }
        splitGroups = validGroups
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    static func sanitizedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(groups)
    }

    func markSplitGroupsStructurallyDirty(schedulePersistence shouldPersist: Bool = true) {
        structuralDirtySet.markSplitGroupsDirty()
        snapshotCache.invalidateSplitGroups()
        if shouldPersist {
            scheduleStructuralPersistence()
        }
    }
}
