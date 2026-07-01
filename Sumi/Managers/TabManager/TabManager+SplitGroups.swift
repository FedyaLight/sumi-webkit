import Foundation

@MainActor
extension TabManager {
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

    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        if let indexed = splitGroupIndexStore.group(containingMemberId: tabId) {
            return indexed
        }
        if let pinId = shortcutPinId(forSplitLookupId: tabId) {
            return splitGroup(containingPinId: pinId)
        }
        return nil
    }

    func splitGroup(with id: UUID) -> SplitGroup? {
        splitGroupIndexStore.group(with: id)
    }

    func splitGroupIds(containing tabId: UUID) -> [UUID] {
        if let groupId = splitGroupIndexStore.groupId(containingMemberId: tabId) {
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
        splitGroupIndexStore.groups.first { splitGroup($0, containsShortcutPinId: pinId) }
    }

    func splitGroupVisualOrderingResolver(for spaceId: UUID) -> SplitGroupVisualOrderingResolver {
        SplitGroupVisualOrderingResolver(
            spaceId: spaceId,
            splitGroups: splitGroups,
            folders: foldersBySpace[spaceId] ?? [],
            spacePinnedPins: spacePinnedPins(for: spaceId)
        )
    }

    func shortcutHostedSplitGroups(for spaceId: UUID) -> [SplitGroup] {
        splitGroupVisualOrderingResolver(for: spaceId).shortcutHostedGroups()
    }

    func shortcutHostedSplitGroup(containingPinId pinId: UUID, in spaceId: UUID? = nil) -> SplitGroup? {
        splitGroups.first { group in
            guard group.isShortcutHosted,
                  splitGroup(group, containsShortcutPinId: pinId)
            else { return false }
            guard let spaceId else { return true }
            return group.hostSpaceId == spaceId
        }
    }

    func regularHostedSplitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        splitGroups.first { group in
            guard !group.isShortcutHosted else { return false }
            return splitGroup(group, containsShortcutPinId: pinId)
        }
    }

    func regularHostedSplitPlaceholderGroup(for pin: ShortcutPin) -> SplitGroup? {
        regularHostedSplitGroup(containingPinId: pin.id)
    }

    func shortcutHostedSplitGroupVisualIndex(_ group: SplitGroup, in spaceId: UUID) -> Int {
        splitGroupVisualOrderingResolver(for: spaceId).visualIndex(for: group)
    }

    func shortcutHostedSplitGroupFolderId(_ group: SplitGroup, in spaceId: UUID) -> UUID? {
        splitGroupVisualOrderingResolver(for: spaceId).folderId(for: group)
    }

    func shortcutHostedSplitGroups(for spaceId: UUID, inFolder folderId: UUID?) -> [SplitGroup] {
        splitGroupVisualOrderingResolver(for: spaceId).shortcutHostedGroups(inFolder: folderId)
    }

    func shortcutHostedSplitHiddenPinIds(for spaceId: UUID) -> Set<UUID> {
        splitGroupVisualOrderingResolver(for: spaceId).hiddenPinIds()
    }

    func topLevelSpacePinnedVisualItems(for spaceId: UUID) -> [SpacePinnedVisualItem] {
        splitGroupVisualOrderingResolver(for: spaceId).topLevelItems().map { item in
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
            adjustedSameContainerInsertionIndex(currentIndex: $0, proposedIndex: index)
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
        withStructuralUpdateTransaction {
            let folderMap = Dictionary(uniqueKeysWithValues: (foldersBySpace[spaceId] ?? []).map { ($0.id, $0) })
            let pins = spacePinnedShortcuts[spaceId] ?? []
            let pinMap = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
            let groupMap = splitGroupIndexStore.groupMap
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

            let remainingFolders = (foldersBySpace[spaceId] ?? [])
                .filter { folder in orderedFolders.contains(where: { $0.id == folder.id }) == false }
            let finalFolders = (orderedFolders + remainingFolders).sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            setFolders(finalFolders, for: spaceId)

            let folderPins = pins.filter { $0.folderId != nil }
            let hiddenOrUnorderedTopLevelPins = pins.filter { pin in
                pin.folderId == nil
                    && !orderedVisiblePinIds.contains(pin.id)
                    && !hiddenSplitPinIds.contains(pin.id)
            }
            let hiddenSplitPins = pins
                .filter { pin in pin.folderId == nil && hiddenSplitPinIds.contains(pin.id) }
                .map { pin in pin.refreshed(index: Int.max) }
            let finalPins = normalizedSpacePinnedShortcuts(
                folderPins + hiddenOrUnorderedTopLevelPins + orderedVisiblePins + hiddenSplitPins
            )
            setSpacePinnedShortcuts(finalPins, for: spaceId)

            if !updatedGroupsById.isEmpty {
                let updatedSplitGroups = splitGroups.map { group in
                    updatedGroupsById[group.id] ?? group
                }
                if updatedSplitGroups != splitGroups {
                    splitGroups = updatedSplitGroups
                    markSplitGroupsStructurallyDirty()
                }
            }
        }
    }

    func visibleSplitTabIds(containing tabId: UUID?) -> [UUID] {
        guard let tabId, let group = splitGroup(containing: tabId) else { return [] }
        return group.tabIds
    }

    func upsertSplitGroup(_ group: SplitGroup, schedulePersistence shouldPersist: Bool = true) {
        let repairedGroup = repairingShortcutBackedMembers(in: group)
        guard let canonicalGroup = repairedGroup.canonicalizedForTiles(),
              canonicalGroup.isValid
        else {
            return
        }
        let sanitized = repairingShortcutBackedMembers(
            in: canonicalGroup.settingActiveTab(canonicalGroup.activeTabId ?? canonicalGroup.tabIds.last)
        )
        if let index = splitGroupIndexStore.index(of: sanitized.id) {
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
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    func removeSplitGroup(id: UUID, schedulePersistence shouldPersist: Bool = true) {
        guard let index = splitGroupIndexStore.index(of: id) else { return }
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
        let validGroups = sanitizedRepairedSplitGroups(groups)
        guard validGroups != splitGroups else { return }
        splitGroups = validGroups
        markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
        requestStructuralPublish()
    }

    func sanitizedRepairedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(groups.map { repairingShortcutBackedMembers(in: $0) })
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

private extension TabManager {
    func splitGroup(_ group: SplitGroup, containsShortcutPinId pinId: UUID) -> Bool {
        if group.containsPin(pinId) || group.tabIds.contains(pinId) {
            return true
        }
        return group.tabIds.contains { leafId in
            tab(for: leafId)?.shortcutPinId == pinId
        }
    }

    func shortcutPinId(forSplitLookupId id: UUID) -> UUID? {
        if shortcutPin(by: id) != nil {
            return id
        }
        return tab(for: id)?.shortcutPinId
    }

    func repairingShortcutBackedMembers(in group: SplitGroup) -> SplitGroup {
        var members = group.members
        var didRepair = false

        for leafId in group.tabIds {
            guard let pin = shortcutPinForSplitLeaf(leafId) else {
                continue
            }

            let existingMember = group.member(for: leafId) ?? group.member(forPinId: pin.id)
            guard let repairedOrigin = repairedSplitMemberOrigin(
                existingMember: existingMember,
                pin: pin,
                in: group
            ) else {
                let filteredMembers = members.filter { member in
                    member.tabId != leafId
                        && member.pinId != pin.id
                        && member.stableId != pin.id
                }
                if filteredMembers.count != members.count {
                    didRepair = true
                    members = filteredMembers
                }
                continue
            }
            let repairedMember = SplitGroupMember(
                tabId: leafId,
                pinId: pin.id,
                origin: repairedOrigin
            )

            let filteredMembers = members.filter { member in
                member.tabId != leafId
                    && member.pinId != pin.id
                    && member.stableId != repairedMember.stableId
            }
            if filteredMembers.count != members.count || existingMember != repairedMember {
                didRepair = true
            }
            members = filteredMembers + [repairedMember]
        }

        guard didRepair else { return group }
        return group.settingMembers(members)
    }

    func repairedSplitMemberOrigin(
        existingMember: SplitGroupMember?,
        pin: ShortcutPin,
        in group: SplitGroup
    ) -> SplitGroupMemberOrigin? {
        if let existingOrigin = existingMember?.origin,
           isValidShortcutBackedOrigin(existingOrigin, for: pin, in: group) {
            return existingOrigin
        }
        return splitMemberOrigin(for: pin, in: group)
    }

    func isValidShortcutBackedOrigin(
        _ origin: SplitGroupMemberOrigin,
        for pin: ShortcutPin,
        in group: SplitGroup
    ) -> Bool {
        switch (pin.role, origin) {
        case (.essential, .essential(let profileId, _)):
            return pin.profileId.map { $0 == profileId } ?? true
        case (.spacePinned, .spacePinned(let spaceId, let folderId, _)):
            guard resolvedSpacePinnedOriginSpaceId(for: pin, in: group) == spaceId else {
                return false
            }
            return folderId.map { self.folderSpaceId(for: $0) == spaceId } ?? true
        case (.spacePinned, .generatedSpacePinnedFromRegular(let spaceId, _)):
            return resolvedSpacePinnedOriginSpaceId(for: pin, in: group) == spaceId
        default:
            return false
        }
    }

    func shortcutPinForSplitLeaf(_ leafId: UUID) -> ShortcutPin? {
        if let pin = shortcutPin(by: leafId) {
            return pin
        }
        guard let pinId = tab(for: leafId)?.shortcutPinId else {
            return nil
        }
        return shortcutPin(by: pinId)
    }

    func splitMemberOrigin(for pin: ShortcutPin, in group: SplitGroup) -> SplitGroupMemberOrigin? {
        switch pin.role {
        case .essential:
            return .essential(profileId: pin.profileId, index: pin.index)
        case .spacePinned:
            guard let spaceId = resolvedSpacePinnedOriginSpaceId(for: pin, in: group) else {
                return nil
            }
            return .spacePinned(
                spaceId: spaceId,
                folderId: pin.folderId.flatMap {
                    folderSpaceId(for: $0) == spaceId ? $0 : nil
                },
                index: pin.index
            )
        }
    }

    func resolvedSpacePinnedOriginSpaceId(for pin: ShortcutPin, in group: SplitGroup) -> UUID? {
        if let spaceId = pin.spaceId,
           spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = group.hostSpaceId,
           spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        return nil
    }
}
