import Foundation

@MainActor
final class ShortcutPinStoreOwner {
    struct Dependencies {
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
        let topLevelSpacePinnedItems: @MainActor (UUID) -> [SpacePinnedShortcutOrderOwner.TopLevelItem]
        let applyTopLevelSpacePinnedOrder: @MainActor ([SpacePinnedShortcutOrderOwner.TopLevelItem], UUID) -> Void
        let insertTopLevelSpacePinnedShortcut: @MainActor (ShortcutPin, UUID, Int) -> ShortcutPin?
        let withSpacePinnedShortcutGroup: @MainActor (UUID, UUID?, (inout [ShortcutPin]) -> Void) -> Void
        let spacePinnedPins: @MainActor (UUID) -> [ShortcutPin]
        let openFolderIfNeeded: @MainActor (UUID) -> Void
        let adjustedSameContainerInsertionIndex: @MainActor (Int, Int) -> Int
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func withPinnedArray(for profileId: UUID, _ mutate: (inout [ShortcutPin]) -> Void) {
        var pins = dependencies.pinnedByProfile()[profileId] ?? []
        mutate(&pins)
        dependencies.setPinnedTabs(reindexed(pins), profileId)
    }

    func reindexed(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        pins.enumerated().map { index, pin in
            ShortcutPin(
                id: pin.id,
                role: pin.role,
                profileId: pin.profileId,
                executionProfileId: pin.executionProfileId,
                spaceId: pin.spaceId,
                index: index,
                folderId: pin.folderId,
                launchURL: pin.launchURL,
                title: pin.title,
                iconAsset: pin.iconAsset
            )
        }
    }

    @discardableResult
    func insert(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        if let folderId = pin.folderId,
           dependencies.runtimeContext()?.isLiveFolder(folderId) == true {
            return nil
        }

        switch pin.role {
        case .essential:
            guard let profileId = pin.profileId else { return nil }
            var destination = dependencies.pinnedByProfile()[profileId] ?? []
            if let existingIndex = destination.firstIndex(where: { $0.id == pin.id }) {
                destination.remove(at: existingIndex)
            }
            guard destination.count < EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems else { return nil }
            let safeIndex = max(0, min(targetIndex, destination.count))
            destination.insert(pin, at: safeIndex)
            let reindexedPins = reindexed(destination)
            dependencies.setPinnedTabs(reindexedPins, profileId)
            return reindexedPins[safeIndex]
        case .spacePinned:
            guard let spaceId = pin.spaceId else { return nil }
            let insertedPin: ShortcutPin?
            if pin.folderId == nil {
                insertedPin = dependencies.insertTopLevelSpacePinnedShortcut(pin, spaceId, targetIndex)
            } else {
                var localInsertedPin: ShortcutPin?
                dependencies.withSpacePinnedShortcutGroup(spaceId, pin.folderId) { destination in
                    let safeIndex = max(0, min(targetIndex, destination.count))
                    destination.insert(pin, at: safeIndex)
                    localInsertedPin = destination[safeIndex].refreshed(index: safeIndex)
                }
                insertedPin = localInsertedPin
            }
            if openTargetFolder, let folderId = pin.folderId {
                dependencies.openFolderIfNeeded(folderId)
            }
            return insertedPin.flatMap { inserted in
                dependencies.spacePinnedPins(spaceId).first(where: { $0.id == inserted.id })
            }
        }
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        let adjustedIndex = adjustedMoveIndex(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            proposedIndex: index
        )
        removeFromContainers(pin)
        let movedPin = clone(
            pin,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: adjustedIndex
        )
        return insert(
            movedPin,
            at: adjustedIndex,
            openTargetFolder: openTargetFolder
        )
    }

    func removeFromContainers(_ pin: ShortcutPin) {
        if pin.role == .essential, let profileId = pin.profileId {
            var pins = dependencies.pinnedByProfile()[profileId] ?? []
            pins.removeAll { $0.id == pin.id }
            dependencies.setPinnedTabs(reindexed(pins), profileId)
        } else if pin.role == .spacePinned, let spaceId = pin.spaceId {
            if pin.folderId == nil {
                let items = dependencies.topLevelSpacePinnedItems(spaceId).filter { item in
                    if case .shortcut(let existingPin) = item { return existingPin.id != pin.id }
                    return true
                }
                dependencies.applyTopLevelSpacePinnedOrder(items, spaceId)
            } else {
                dependencies.withSpacePinnedShortcutGroup(spaceId, pin.folderId) { pins in
                    pins.removeAll { $0.id == pin.id }
                }
            }
        }
    }
}

private extension ShortcutPinStoreOwner {
    func adjustedMoveIndex(
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
            currentIndex = dependencies.pinnedByProfile()[profileId]?.firstIndex(where: { $0.id == pin.id })
        case .spacePinned:
            guard let spaceId else { return proposedIndex }
            if folderId == nil {
                currentIndex = dependencies.topLevelSpacePinnedItems(spaceId).firstIndex {
                    if case .shortcut(let existingPin) = $0 {
                        return existingPin.id == pin.id
                    }
                    return false
                }
            } else {
                currentIndex = dependencies.spacePinnedPins(spaceId)
                    .filter { $0.folderId == folderId }
                    .sorted {
                        if $0.index != $1.index { return $0.index < $1.index }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    .firstIndex(where: { $0.id == pin.id })
            }
        }

        guard let currentIndex else { return proposedIndex }
        return dependencies.adjustedSameContainerInsertionIndex(currentIndex, proposedIndex)
    }

    func clone(
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
}

extension ShortcutPinStoreOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            runtimeContext: { [weak tabManager] in
                tabManager?.runtimeContext
            },
            pinnedByProfile: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:]
            },
            setPinnedTabs: { [weak tabManager] pins, profileId in
                tabManager?.structuralCollectionMutationOwner.setPinnedTabs(pins, for: profileId)
            },
            topLevelSpacePinnedItems: { [weak tabManager] spaceId in
                tabManager?.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId) ?? []
            },
            applyTopLevelSpacePinnedOrder: { [weak tabManager] items, spaceId in
                tabManager?.spacePinnedStructureOwner.applyTopLevelSpacePinnedOrder(items, for: spaceId)
            },
            insertTopLevelSpacePinnedShortcut: { [weak tabManager] pin, spaceId, targetIndex in
                tabManager?.spacePinnedStructureOwner.insertTopLevelSpacePinnedShortcut(pin, in: spaceId, at: targetIndex)
            },
            withSpacePinnedShortcutGroup: { [weak tabManager] spaceId, folderId, mutate in
                tabManager?.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: folderId) { pins in
                    mutate(&pins)
                }
            },
            spacePinnedPins: { [weak tabManager] spaceId in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId) ?? []
            },
            openFolderIfNeeded: { [weak tabManager] folderId in
                tabManager?.folderMutationOwner.openFolderIfNeeded(folderId)
            },
            adjustedSameContainerInsertionIndex: { [weak tabManager] currentIndex, proposedIndex in
                guard let tabManager else { return proposedIndex }
                return tabManager.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                    currentIndex: currentIndex,
                    proposedIndex: proposedIndex
                )
            }
        )
    }
}
