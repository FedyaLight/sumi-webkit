import Foundation

extension TabManager {
    func withPinnedArray(for profileId: UUID, _ mutate: (inout [ShortcutPin]) -> Void) {
        var arr = pinnedByProfile[profileId] ?? []
        mutate(&arr)
        setPinnedTabs(reindexed(arr), for: profileId)
    }

    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId else { return [] }
        return activeShortcutTabs(role: .essential).filter { tab in
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(by: shortcutId) else { return false }
            return pin.profileId == profileId
        }
    }

    func makeShortcutPin(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        folderId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            executionProfileId: shortcutExecutionProfileId(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId
            ),
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: tab.url,
            title: tab.name
        )
    }

    func resolvedLiveSpaceId(for pin: ShortcutPin, currentSpaceId: UUID?) -> UUID? {
        switch pin.role {
        case .essential:
            return nil
        case .spacePinned:
            return pin.spaceId ?? currentSpaceId
        }
    }

    func resolvedExecutionProfileId(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> UUID? {
        if let executionProfileId = pin.executionProfileId {
            return executionProfileId
        }

        switch pin.role {
        case .essential:
            return pin.profileId
        case .spacePinned:
            return (pin.spaceId ?? currentSpaceId).flatMap { spaceId in
                spaces.first(where: { $0.id == spaceId })?.profileId
            }
        }
    }

    func resolvedFaviconPartition(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> SumiFaviconPartition {
        let profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
        guard let profileId,
              let profile = runtimeContext?.profile(with: profileId)
        else {
            return .regular(profileId)
        }
        return faviconService.partition(profile: profile)
    }

    @discardableResult
    func convertShortcutPinToRegularTab(_ pin: ShortcutPin, in targetSpaceId: UUID, at targetIndex: Int? = nil) -> Bool {
        withStructuralUpdateTransaction {
            _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: targetIndex)
            removeShortcutPinFromContainers(pin)
            scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    func insertShortcutPin(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        if let folderId = pin.folderId,
           runtimeContext?.isLiveFolder(folderId) == true {
            return nil
        }

        switch pin.role {
        case .essential:
            guard let profileId = pin.profileId else { return nil }
            var destination = pinnedByProfile[profileId] ?? []
            if let existingIndex = destination.firstIndex(where: { $0.id == pin.id }) {
                destination.remove(at: existingIndex)
            }
            guard destination.count < EssentialsCapacityPolicy.maxItems else { return nil }
            let safeIndex = max(0, min(targetIndex, destination.count))
            destination.insert(pin, at: safeIndex)
            let reindexedPins = reindexed(destination)
            setPinnedTabs(reindexedPins, for: profileId)
            return reindexedPins[safeIndex]
        case .spacePinned:
            guard let spaceId = pin.spaceId else { return nil }
            let insertedPin: ShortcutPin?
            if pin.folderId == nil {
                insertedPin = insertTopLevelSpacePinnedShortcut(pin, in: spaceId, at: targetIndex)
            } else {
                var localInsertedPin: ShortcutPin?
                withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { destination in
                    let safeIndex = max(0, min(targetIndex, destination.count))
                    destination.insert(pin, at: safeIndex)
                    localInsertedPin = destination[safeIndex].refreshed(index: safeIndex)
                }
                insertedPin = localInsertedPin
            }
            if openTargetFolder, let folderId = pin.folderId {
                openFolderIfNeeded(folderId)
            }
            return insertedPin.flatMap { inserted in
                spacePinnedShortcuts[spaceId]?.first(where: { $0.id == inserted.id })
            }
        }
    }

    @discardableResult
    func moveShortcutPin(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            let adjustedIndex = adjustedShortcutMoveIndex(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                proposedIndex: index
            )
            removeShortcutPinFromContainers(pin)
            let movedPin = cloneShortcutPin(
                pin,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: adjustedIndex
            )
            let inserted = insertShortcutPin(
                movedPin,
                at: adjustedIndex,
                openTargetFolder: openTargetFolder
            )
            if let inserted {
                updateTransientShortcutBindings(for: inserted)
            }
            scheduleStructuralPersistence()
            return inserted
        }
    }

    @discardableResult
    func convertTabToShortcutPin(
        _ tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        at targetIndex: Int,
        openTargetFolder: Bool = true,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            let pin = makeShortcutPin(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: targetIndex
            )
            guard let insertedPin = insertShortcutPin(
                pin,
                at: targetIndex,
                openTargetFolder: openTargetFolder
            ) else { return nil }

            if !convertDisplayedTabToShortcutLiveInstances(
                tab,
                pin: insertedPin,
                preferredWindowId: preferredWindowId
            ) {
                removeTab(tab.id)
            }
            scheduleStructuralPersistence()
            return insertedPin
        }
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            switch (operation.fromContainer, operation.toContainer) {
            case (.essentials, .essentials):
                return reorderEssential(pin, to: operation.toIndex)

            case (.essentials, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.essentials, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.essentials, .spaceRegular(let targetSpaceId)):
                return convertShortcutPinToRegularTab(pin, in: targetSpaceId, at: operation.toIndex)

            case (.spacePinned, .essentials),
                 (.folder, .essentials):
                guard let currentProfileId = resolvedEssentialsProfileId(for: operation) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .essential,
                    profileId: currentProfileId,
                    spaceId: nil,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .folder(let targetFolderId)),
                 (.folder, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.folder, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spaceRegular(let targetSpaceId)),
                 (.folder, .spaceRegular(let targetSpaceId)):
                removeShortcutPinFromContainers(pin)
                _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: operation.toIndex)
                scheduleStructuralPersistence()
                return true

            case (.spaceRegular, _),
                 (.none, _),
                 (_, .none):
                return false
            }
        }
    }
}

private extension TabManager {
    func shortcutExecutionProfileId(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?
    ) -> UUID? {
        guard let tabProfileId = tab.profileId else { return nil }

        let containerProfileId: UUID?
        switch role {
        case .essential:
            containerProfileId = profileId
        case .spacePinned:
            containerProfileId = spaceId.flatMap { targetSpaceId in
                spaces.first(where: { $0.id == targetSpaceId })?.profileId
            }
        }

        return tabProfileId == containerProfileId ? nil : tabProfileId
    }

    func adjustedShortcutMoveIndex(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        proposedIndex: Int
    ) -> Int {
        guard pin.role == role,
              pin.profileId == profileId,
              pin.spaceId == spaceId,
              pin.folderId == folderId else {
            return proposedIndex
        }

        let currentIndex: Int?
        switch role {
        case .essential:
            guard let profileId else { return proposedIndex }
            currentIndex = pinnedByProfile[profileId]?.firstIndex(where: { $0.id == pin.id })
        case .spacePinned:
            guard let spaceId else { return proposedIndex }
            if folderId == nil {
                currentIndex = topLevelSpacePinnedItems(for: spaceId).firstIndex {
                    if case .shortcut(let existingPin) = $0 {
                        return existingPin.id == pin.id
                    }
                    return false
                }
            } else {
                currentIndex = spacePinnedPins(for: spaceId)
                    .filter { $0.folderId == folderId }
                    .sorted {
                        if $0.index != $1.index { return $0.index < $1.index }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    .firstIndex(where: { $0.id == pin.id })
            }
        }

        guard let currentIndex else { return proposedIndex }
        return adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
    }

    func cloneShortcutPin(
        _ pin: ShortcutPin,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: pin.id,
            role: role,
            profileId: profileId,
            executionProfileId: pin.executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            iconAsset: pin.iconAsset
        )
    }

    func removeShortcutPinFromContainers(_ pin: ShortcutPin) {
        if pin.role == .essential, let profileId = pin.profileId {
            var arr = pinnedByProfile[profileId] ?? []
            arr.removeAll { $0.id == pin.id }
            setPinnedTabs(reindexed(arr), for: profileId)
        } else if pin.role == .spacePinned, let spaceId = pin.spaceId {
            if pin.folderId == nil {
                let items = topLevelSpacePinnedItems(for: spaceId).filter { item in
                    if case .shortcut(let existingPin) = item { return existingPin.id != pin.id }
                    return true
                }
                applyTopLevelSpacePinnedOrder(items, for: spaceId)
            } else {
                withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { arr in
                    arr.removeAll { $0.id == pin.id }
                }
            }
        }
    }

}
