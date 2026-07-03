import Foundation

/// Owns split group structural membership: lookup by member or shortcut pin,
/// visual ordering of shortcut-hosted groups, and upsert/remove/replace
/// mutations that keep the persisted split group collection sane.
@MainActor
final class TabSplitGroupStructureOwner {
    enum SpacePinnedVisualItem: Hashable {
        case folder(UUID)
        case shortcut(UUID)
        case splitGroup(UUID)

        var id: UUID {
            switch self {
            case .folder(let id), .shortcut(let id), .splitGroup(let id):
                return id
            }
        }
    }

    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    // MARK: - Lookup

    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        if let indexed = tabManager.splitGroupCollectionStateOwner.group(containingMemberId: tabId) {
            return indexed
        }
        if let pinId = shortcutPinId(forSplitLookupId: tabId) {
            return splitGroup(containingPinId: pinId)
        }
        return nil
    }

    func splitGroupIds(containing tabId: UUID) -> [UUID] {
        if let groupId = tabManager.splitGroupCollectionStateOwner.groupId(containingMemberId: tabId) {
            return [groupId]
        }
        guard let pinId = shortcutPinId(forSplitLookupId: tabId),
              let group = splitGroup(containingPinId: pinId)
        else {
            return []
        }
        return [group.id]
    }

    func splitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        tabManager.splitGroupCollectionStateOwner.indexedGroups.first {
            splitGroup($0, containsShortcutPinId: pinId)
        }
    }

    func shortcutHostedSplitGroup(containingPinId pinId: UUID, in spaceId: UUID?) -> SplitGroup? {
        tabManager.splitGroups.first { group in
            guard group.isShortcutHosted,
                  splitGroup(group, containsShortcutPinId: pinId)
            else { return false }
            guard let spaceId else { return true }
            return group.hostSpaceId == spaceId
        }
    }

    func regularHostedSplitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        tabManager.splitGroups.first { group in
            guard !group.isShortcutHosted else { return false }
            return splitGroup(group, containsShortcutPinId: pinId)
        }
    }

    func visibleSplitTabIds(containing tabId: UUID?) -> [UUID] {
        guard let tabId, let group = splitGroup(containing: tabId) else { return [] }
        return group.tabIds
    }

    // MARK: - Visual Ordering

    func visualOrderingResolver(for spaceId: UUID) -> SplitGroupVisualOrderingResolver {
        SplitGroupVisualOrderingResolver(
            spaceId: spaceId,
            splitGroups: tabManager.splitGroups,
            folders: tabManager.foldersBySpace[spaceId] ?? [],
            spacePinnedPins: tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
        )
    }

    func shortcutHostedSplitGroups(for spaceId: UUID) -> [SplitGroup] {
        visualOrderingResolver(for: spaceId).shortcutHostedGroups()
    }

    func shortcutHostedSplitGroups(for spaceId: UUID, inFolder folderId: UUID?) -> [SplitGroup] {
        visualOrderingResolver(for: spaceId).shortcutHostedGroups(inFolder: folderId)
    }

    func shortcutHostedSplitGroupFolderId(_ group: SplitGroup, in spaceId: UUID) -> UUID? {
        visualOrderingResolver(for: spaceId).folderId(for: group)
    }

    func topLevelSpacePinnedVisualItems(for spaceId: UUID) -> [SpacePinnedVisualItem] {
        visualOrderingResolver(for: spaceId).topLevelItems().map { item in
            switch item {
            case .folder(let id):
                return .folder(id)
            case .shortcut(let id):
                return .shortcut(id)
            case .splitGroup(let id):
                return .splitGroup(id)
            }
        }
    }

    @discardableResult
    func moveShortcutHostedSplitGroup(_ group: SplitGroup, in spaceId: UUID, to index: Int) -> Bool {
        guard group.isShortcutHosted,
              group.hostSpaceId == spaceId else {
            return false
        }

        let visualItems = topLevelSpacePinnedVisualItems(for: spaceId)
        let currentIndex = visualItems.firstIndex(where: {
            if case .splitGroup(let groupId) = $0 { return groupId == group.id }
            return false
        })
        let adjustedIndex = currentIndex.map {
            tabManager.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(currentIndex: $0, proposedIndex: index)
        } ?? index
        var reorderedItems = visualItems
        let movingItem: SpacePinnedVisualItem
        if let currentIndex {
            movingItem = reorderedItems.remove(at: currentIndex)
        } else {
            movingItem = .splitGroup(group.id)
        }
        let safeIndex = max(0, min(adjustedIndex, reorderedItems.count))
        reorderedItems.insert(movingItem, at: safeIndex)

        guard reorderedItems != visualItems else { return false }
        applyTopLevelSpacePinnedVisualOrder(reorderedItems, for: spaceId)
        return true
    }

    private func applyTopLevelSpacePinnedVisualOrder(
        _ items: [SpacePinnedVisualItem],
        for spaceId: UUID
    ) {
        tabManager.withStructuralUpdateTransaction {
            let folderMap = Dictionary(
                uniqueKeysWithValues: (tabManager.foldersBySpace[spaceId] ?? []).map { ($0.id, $0) }
            )
            let pins = tabManager.spacePinnedShortcuts[spaceId] ?? []
            let pinMap = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
            let groupMap = tabManager.splitGroupCollectionStateOwner.groupMap
            var orderedFolders: [TabFolder] = []
            var orderedVisiblePins: [ShortcutPin] = []
            var orderedVisiblePinIds = Set<UUID>()
            var hiddenSplitPinIds = Set<UUID>()
            var updatedGroupsById: [UUID: SplitGroup] = [:]

            for (index, item) in items.enumerated() {
                switch item {
                case .folder(let folderId):
                    guard let folder = folderMap[folderId] else { continue }
                    folder.index = index
                    folder.spaceId = spaceId
                    folder.parentFolderId = nil
                    orderedFolders.append(folder)

                case .shortcut(let pinId):
                    guard let pin = pinMap[pinId] else { continue }
                    orderedVisiblePinIds.insert(pin.id)
                    orderedVisiblePins.append(
                        pin
                            .refreshed(index: index)
                            .moved(toFolderId: nil)
                    )

                case .splitGroup(let groupId):
                    guard let group = groupMap[groupId],
                          group.isShortcutHosted,
                          group.hostSpaceId == spaceId else {
                        continue
                    }
                    hiddenSplitPinIds.formUnion(group.shortcutPinIds)
                    updatedGroupsById[group.id] = group.settingHost(
                        group.host.settingShortcutPinnedIndex(index)
                    )
                }
            }

            let remainingFolders = (tabManager.foldersBySpace[spaceId] ?? [])
                .filter { folder in orderedFolders.contains(where: { $0.id == folder.id }) == false }
            let finalFolders = (orderedFolders + remainingFolders).sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            tabManager.setFolders(finalFolders, for: spaceId)

            let folderPins = pins.filter { $0.folderId != nil }
            let hiddenOrUnorderedTopLevelPins = pins.filter { pin in
                pin.folderId == nil
                    && !orderedVisiblePinIds.contains(pin.id)
                    && !hiddenSplitPinIds.contains(pin.id)
            }
            let hiddenSplitPins = pins
                .filter { pin in pin.folderId == nil && hiddenSplitPinIds.contains(pin.id) }
                .map { pin in pin.refreshed(index: Int.max) }
            let finalPins = tabManager.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(
                folderPins + hiddenOrUnorderedTopLevelPins + orderedVisiblePins + hiddenSplitPins
            )
            tabManager.setSpacePinnedShortcuts(finalPins, for: spaceId)

            if !updatedGroupsById.isEmpty {
                let updatedSplitGroups = tabManager.splitGroups.map { group in
                    updatedGroupsById[group.id] ?? group
                }
                if updatedSplitGroups != tabManager.splitGroups {
                    tabManager.splitGroups = updatedSplitGroups
                    markSplitGroupsStructurallyDirty(schedulePersistence: true)
                }
            }
        }
    }

    // MARK: - Mutation

    func upsertSplitGroup(_ group: SplitGroup, schedulePersistence shouldPersist: Bool = true) {
        let repairedGroup = tabManager.splitGroupRepairOwner.repairingShortcutBackedMembers(in: group)
        guard let canonicalGroup = repairedGroup.canonicalizedForTiles(),
              canonicalGroup.isValid
        else {
            return
        }
        let sanitized = tabManager.splitGroupRepairOwner.repairingShortcutBackedMembers(
            in: canonicalGroup.settingActiveTab(canonicalGroup.activeTabId ?? canonicalGroup.tabIds.last)
        )
        if let index = tabManager.splitGroupCollectionStateOwner.index(of: sanitized.id) {
            tabManager.splitGroups[index] = sanitized
        } else {
            let memberIds = Set(sanitized.tabIds).union(sanitized.shortcutPinIds)
            tabManager.splitGroups.removeAll { existing in
                guard existing.id != sanitized.id else { return false }
                let existingMemberIds = Set(existing.tabIds).union(existing.shortcutPinIds)
                return existingMemberIds.contains { memberIds.contains($0) }
            }
            tabManager.splitGroups.append(sanitized)
        }
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        tabManager.requestStructuralPublish()
    }

    func removeSplitGroup(id: UUID, schedulePersistence shouldPersist: Bool = true) {
        guard let index = tabManager.splitGroupCollectionStateOwner.index(of: id) else { return }
        tabManager.splitGroups.remove(at: index)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        tabManager.requestStructuralPublish()
    }

    func removeSplitGroups(containing tabId: UUID, schedulePersistence shouldPersist: Bool = true) {
        let updated = tabManager.splitGroups.compactMap { group in
            group.contains(tabId) ? group.removing(tabId: tabId) : group
        }
        guard updated != tabManager.splitGroups else { return }
        tabManager.splitGroups = updated
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        tabManager.requestStructuralPublish()
    }

    func replaceSplitGroups(_ groups: [SplitGroup], schedulePersistence shouldPersist: Bool = true) {
        let validGroups = sanitizedRepairedSplitGroups(groups)
        guard validGroups != tabManager.splitGroups else { return }
        tabManager.splitGroups = validGroups
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        tabManager.requestStructuralPublish()
    }

    func sanitizedRepairedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(groups.map {
            tabManager.splitGroupRepairOwner.repairingShortcutBackedMembers(in: $0)
        })
    }

    func markSplitGroupsStructurallyDirty(schedulePersistence shouldPersist: Bool = true) {
        tabManager.structuralPersistence.markSplitGroupsStructurallyDirty()
        if shouldPersist {
            tabManager.scheduleStructuralPersistence()
        }
    }

    // MARK: - Private

    private func splitGroup(_ group: SplitGroup, containsShortcutPinId pinId: UUID) -> Bool {
        if group.containsPin(pinId) || group.tabIds.contains(pinId) {
            return true
        }
        return group.tabIds.contains { leafId in
            tabManager.tab(for: leafId)?.shortcutPinId == pinId
        }
    }

    private func shortcutPinId(forSplitLookupId id: UUID) -> UUID? {
        if tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: id) != nil {
            return id
        }
        return tabManager.tab(for: id)?.shortcutPinId
    }
}
