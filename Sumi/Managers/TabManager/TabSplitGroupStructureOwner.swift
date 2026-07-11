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

    struct Dependencies {
        let splitGroupStateOwner: SplitGroupCollectionStateOwner
        let splitGroups: () -> [SplitGroup]
        let replaceSplitGroups: ([SplitGroup]) -> Void
        let folders: (UUID) -> [TabFolder]
        let spacePinnedPins: (UUID) -> [ShortcutPin]
        let adjustedSameContainerInsertionIndex: (Int, Int) -> Int
        let withStructuralUpdateTransaction: (@MainActor () -> Void) -> Void
        let setFolders: ([TabFolder], UUID) -> Void
        let normalizedSpacePinnedShortcuts: ([ShortcutPin]) -> [ShortcutPin]
        let setSpacePinnedShortcuts: ([ShortcutPin], UUID) -> Void
        let repairShortcutBackedMembers: (SplitGroup) -> SplitGroup
        let requestStructuralPublish: () -> Void
        let markSplitGroupsStructurallyDirty: () -> Void
        let scheduleStructuralPersistence: () -> Void
        let tab: (UUID) -> Tab?
        let shortcutPin: (UUID) -> ShortcutPin?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Lookup

    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        if let indexed = dependencies.splitGroupStateOwner.group(containingMemberId: tabId) {
            return indexed
        }
        if let pinId = shortcutPinId(forSplitLookupId: tabId) {
            return splitGroup(containingPinId: pinId)
        }
        return nil
    }

    func splitGroupIds(containing tabId: UUID) -> [UUID] {
        if let groupId = dependencies.splitGroupStateOwner.groupId(containingMemberId: tabId) {
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
        dependencies.splitGroupStateOwner.indexedGroups.first {
            splitGroup($0, containsShortcutPinId: pinId)
        }
    }

    func regularHostedSplitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        dependencies.splitGroups().first { group in
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
            splitGroups: dependencies.splitGroups(),
            folders: dependencies.folders(spaceId),
            spacePinnedPins: dependencies.spacePinnedPins(spaceId)
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
            dependencies.adjustedSameContainerInsertionIndex($0, index)
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
        dependencies.withStructuralUpdateTransaction {
            let folderMap = Dictionary(
                uniqueKeysWithValues: dependencies.folders(spaceId).map { ($0.id, $0) }
            )
            let pins = dependencies.spacePinnedPins(spaceId)
            let pinMap = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
            let groupMap = dependencies.splitGroupStateOwner.groupMap
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

            let remainingFolders = dependencies.folders(spaceId)
                .filter { folder in orderedFolders.contains(where: { $0.id == folder.id }) == false }
            let finalFolders = (orderedFolders + remainingFolders).sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            dependencies.setFolders(finalFolders, spaceId)

            let folderPins = pins.filter { $0.folderId != nil }
            let hiddenOrUnorderedTopLevelPins = pins.filter { pin in
                pin.folderId == nil
                    && !orderedVisiblePinIds.contains(pin.id)
                    && !hiddenSplitPinIds.contains(pin.id)
            }
            let hiddenSplitPins = pins
                .filter { pin in pin.folderId == nil && hiddenSplitPinIds.contains(pin.id) }
                .map { pin in pin.refreshed(index: Int.max) }
            let finalPins = dependencies.normalizedSpacePinnedShortcuts(
                folderPins + hiddenOrUnorderedTopLevelPins + orderedVisiblePins + hiddenSplitPins
            )
            dependencies.setSpacePinnedShortcuts(finalPins, spaceId)

            if !updatedGroupsById.isEmpty {
                let updatedSplitGroups = dependencies.splitGroups().map { group in
                    updatedGroupsById[group.id] ?? group
                }
                if updatedSplitGroups != dependencies.splitGroups() {
                    dependencies.replaceSplitGroups(updatedSplitGroups)
                    markSplitGroupsStructurallyDirty(schedulePersistence: true)
                }
            }
        }
    }

    // MARK: - Mutation

    func upsertSplitGroup(_ group: SplitGroup, schedulePersistence shouldPersist: Bool = true) {
        let repairedGroup = dependencies.repairShortcutBackedMembers(group)
        guard let canonicalGroup = repairedGroup.canonicalizedForTiles(),
              canonicalGroup.isValid
        else {
            return
        }
        let sanitized = dependencies.repairShortcutBackedMembers(
            canonicalGroup.settingActiveTab(canonicalGroup.activeTabId ?? canonicalGroup.tabIds.last)
        )
        var splitGroups = dependencies.splitGroups()
        if let index = dependencies.splitGroupStateOwner.index(of: sanitized.id) {
            splitGroups[index] = sanitized
        } else {
            let memberIds = Set(sanitized.tabIds).union(sanitized.shortcutPinIds)
            splitGroups.removeAll { existing in
                guard existing.id != sanitized.id else { return false }
                let existingMemberIds = Set(existing.tabIds).union(existing.shortcutPinIds)
                return existingMemberIds.contains { memberIds.contains($0) }
            }
            splitGroups.append(sanitized)
        }
        dependencies.replaceSplitGroups(splitGroups)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        dependencies.requestStructuralPublish()
    }

    func removeSplitGroup(id: UUID, schedulePersistence shouldPersist: Bool = true) {
        guard let index = dependencies.splitGroupStateOwner.index(of: id) else { return }
        var splitGroups = dependencies.splitGroups()
        splitGroups.remove(at: index)
        dependencies.replaceSplitGroups(splitGroups)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        dependencies.requestStructuralPublish()
    }

    func removeSplitGroups(containing tabId: UUID, schedulePersistence shouldPersist: Bool = true) {
        removeSplitGroups(
            hostedBy: nil,
            containingAny: [tabId],
            schedulePersistence: shouldPersist
        )
    }

    @discardableResult
    func removeSplitGroups(
        hostedBy spaceId: UUID? = nil,
        containingAny memberIds: Set<UUID>,
        schedulePersistence shouldPersist: Bool = true
    ) -> Set<UUID> {
        let current = dependencies.splitGroups()
        var removedGroupIds = Set<UUID>()
        let updated = current.compactMap { group -> SplitGroup? in
            if let spaceId, group.hostSpaceId == spaceId {
                removedGroupIds.insert(group.id)
                return nil
            }

            let matchedTabIds = memberIds.reduce(into: Set<UUID>()) { result, memberId in
                if let member = group.member(for: memberId) {
                    result.insert(member.tabId)
                } else if group.tabIds.contains(memberId) {
                    result.insert(memberId)
                }
            }
            let tabIds = group.tabIds.filter(matchedTabIds.contains)
            let revised = tabIds.reduce(Optional(group)) { partial, tabId in
                partial?.removing(tabId: tabId)
            }
            if revised == nil, !tabIds.isEmpty {
                removedGroupIds.insert(group.id)
            }
            return revised
        }
        guard updated != current else { return [] }
        dependencies.replaceSplitGroups(updated)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        dependencies.requestStructuralPublish()
        return removedGroupIds
    }

    func replaceSplitGroups(_ groups: [SplitGroup], schedulePersistence shouldPersist: Bool = true) {
        let validGroups = sanitizedRepairedSplitGroups(groups)
        guard validGroups != dependencies.splitGroups() else { return }
        dependencies.replaceSplitGroups(validGroups)
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        dependencies.requestStructuralPublish()
    }

    func sanitizedRepairedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(groups.map {
            dependencies.repairShortcutBackedMembers($0)
        })
    }

    func markSplitGroupsStructurallyDirty(schedulePersistence shouldPersist: Bool = true) {
        dependencies.markSplitGroupsStructurallyDirty()
        if shouldPersist {
            dependencies.scheduleStructuralPersistence()
        }
    }

    // MARK: - Private

    private func splitGroup(_ group: SplitGroup, containsShortcutPinId pinId: UUID) -> Bool {
        if group.containsPin(pinId) || group.tabIds.contains(pinId) {
            return true
        }
        return group.tabIds.contains { leafId in
            dependencies.tab(leafId)?.shortcutPinId == pinId
        }
    }

    private func shortcutPinId(forSplitLookupId id: UUID) -> UUID? {
        if dependencies.shortcutPin(id) != nil {
            return id
        }
        return dependencies.tab(id)?.shortcutPinId
    }
}

extension TabSplitGroupStructureOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            splitGroupStateOwner: tabManager.splitGroupCollectionStateOwner,
            splitGroups: { [weak tabManager] in
                tabManager?.splitGroupCollectionStateOwner.splitGroups ?? []
            },
            replaceSplitGroups: { [weak tabManager] splitGroups in
                tabManager?.objectWillChange.send()
                tabManager?.splitGroupCollectionStateOwner.replaceSplitGroups(splitGroups)
            },
            folders: { [weak tabManager] spaceId in
                tabManager?.folderCollectionStateOwner.folders(for: spaceId) ?? []
            },
            spacePinnedPins: { [weak tabManager] spaceId in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId) ?? []
            },
            adjustedSameContainerInsertionIndex: { [weak tabManager] currentIndex, proposedIndex in
                tabManager?.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                    currentIndex: currentIndex,
                    proposedIndex: proposedIndex
                ) ?? proposedIndex
            },
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            setFolders: { [weak tabManager] folders, spaceId in
                tabManager?.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
            },
            normalizedSpacePinnedShortcuts: { [weak tabManager] pins in
                tabManager?.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(pins) ?? pins
            },
            setSpacePinnedShortcuts: { [weak tabManager] pins, spaceId in
                tabManager?.structuralCollectionMutationOwner.setSpacePinnedShortcuts(pins, for: spaceId)
            },
            repairShortcutBackedMembers: { [weak tabManager] group in
                tabManager?.splitGroupRepairOwner.repairingShortcutBackedMembers(in: group) ?? group
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.requestPublish()
            },
            markSplitGroupsStructurallyDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markSplitGroupsStructurallyDirty()
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            tab: { [weak tabManager] tabId in
                tabManager?.tabCollectionMembershipOwner.tab(for: tabId)
            },
            shortcutPin: { [weak tabManager] pinId in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
            }
        )
    }
}
