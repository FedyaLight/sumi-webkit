import Foundation
import SumiDomain

@MainActor
final class ShortcutPinStoreOwner {
    struct Dependencies {
        let destinationValidator: ShortcutPinDestinationValidator
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
        let topLevelSpacePinnedItems: @MainActor (UUID) -> [SpacePinnedShortcutOrderOwner.TopLevelItem]
        let applyTopLevelSpacePinnedOrder: @MainActor ([SpacePinnedShortcutOrderOwner.TopLevelItem], UUID) -> Void
        let insertTopLevelSpacePinnedShortcut: @MainActor (ShortcutPin, UUID, Int) -> ShortcutPin?
        let withSpacePinnedShortcutGroup: @MainActor (UUID, UUID?, (inout [ShortcutPin]) -> Void) -> Void
        let spacePinnedPins: @MainActor (UUID) -> [ShortcutPin]
        let folderOpenState: TabFolderOpenStateService
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
        guard dependencies.destinationValidator.accepts(
            role: pin.role,
            spaceId: pin.spaceId,
            folderId: pin.folderId
        ) else { return nil }
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
                dependencies.folderOpenState.openFolderIfNeeded(folderId)
            }
            return insertedPin.flatMap { inserted in
                dependencies.spacePinnedPins(spaceId).first(where: { $0.id == inserted.id })
            }
        }
    }

    func previewInsert(
        _ pin: ShortcutPin,
        at targetIndex: Int
    ) -> ShortcutPin? {
        guard dependencies.destinationValidator.accepts(
            role: pin.role,
            spaceId: pin.spaceId,
            folderId: pin.folderId
        ) else { return nil }
        let destinationCount: Int
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId else { return nil }
            let destination = dependencies.pinnedByProfile()[profileID] ?? []
            destinationCount = destination.filter { $0.id != pin.id }.count
            guard destinationCount
                    < EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems
            else { return nil }
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            if let folderID = pin.folderId {
                destinationCount = dependencies.spacePinnedPins(spaceID)
                    .filter { $0.folderId == folderID && $0.id != pin.id }
                    .count
            } else {
                destinationCount = dependencies.topLevelSpacePinnedItems(
                    spaceID
                ).count
            }
        }
        return pin.refreshed(index: max(0, min(targetIndex, destinationCount)))
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
        moveResolved(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index,
            openTargetFolder: openTargetFolder,
            applying: nil
        )
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true,
        applying: @escaping (ShortcutPin) -> Bool
    ) -> ShortcutPin? {
        moveResolved(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index,
            openTargetFolder: openTargetFolder,
            applying: applying
        )
    }

    private func moveResolved(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool,
        applying: ((ShortcutPin) -> Bool)?
    ) -> ShortcutPin? {
        guard let sourcePin = canonicalSource(matching: pin) else { return nil }
        guard let movedPin = previewMove(
            sourcePin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            proposedIndex: index
        ) else { return nil }
        removeFromContainers(sourcePin)
        guard let inserted = insert(
            movedPin,
            at: movedPin.index,
            openTargetFolder: false
        ) else {
            restoreToSource(sourcePin)
            return nil
        }
        if let applying, applying(inserted) == false {
            removeFromContainers(inserted)
            restoreToSource(sourcePin)
            return nil
        }
        if openTargetFolder, let folderId = inserted.folderId {
            dependencies.folderOpenState.openFolderIfNeeded(folderId)
        }
        return inserted
    }

    func previewMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        proposedIndex: Int
    ) -> ShortcutPin? {
        guard let sourcePin = canonicalSource(matching: pin),
              acceptsMove(
                  sourcePin,
                  to: role,
                  profileId: profileId,
                  spaceId: spaceId,
                  folderId: folderId
              ) else { return nil }
        return clone(
            sourcePin,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: adjustedMoveIndex(
                sourcePin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                proposedIndex: proposedIndex
            )
        )
    }

    /// Exact preflight used by compound split/pin transactions. This performs
    /// the same catalog and capacity checks as `move` without mutating state or
    /// scheduling persistence.
    func canMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        previewMove(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            proposedIndex: pin.index
        ) != nil
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
    func canonicalSource(matching pin: ShortcutPin) -> ShortcutPin? {
        switch pin.role {
        case .essential:
            guard let profileId = pin.profileId else { return nil }
            return dependencies.pinnedByProfile()[profileId]?
                .first { $0.id == pin.id }
        case .spacePinned:
            guard let spaceId = pin.spaceId,
                  let stored = dependencies.spacePinnedPins(spaceId)
                    .first(where: { $0.id == pin.id }),
                  stored.folderId == pin.folderId else {
                return nil
            }
            return stored
        }
    }

    func acceptsMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        guard dependencies.destinationValidator.accepts(
            role: role,
            spaceId: spaceId,
            folderId: folderId
        ) else { return false }
        switch role {
        case .essential:
            guard let profileId else { return false }
            let destinationCount = (dependencies.pinnedByProfile()[profileId] ?? [])
                .filter { $0.id != pin.id }
                .count
            return destinationCount
                < EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems
        case .spacePinned:
            return spaceId != nil
        }
    }

    func restoreToSource(_ pin: ShortcutPin) {
        switch pin.role {
        case .essential:
            guard let profileId = pin.profileId else { return }
            var pins = dependencies.pinnedByProfile()[profileId] ?? []
            pins.removeAll { $0.id == pin.id }
            pins.insert(pin, at: max(0, min(pin.index, pins.count)))
            dependencies.setPinnedTabs(reindexed(pins), profileId)
        case .spacePinned:
            guard let spaceId = pin.spaceId else { return }
            if pin.folderId == nil {
                _ = dependencies.insertTopLevelSpacePinnedShortcut(
                    pin,
                    spaceId,
                    pin.index
                )
            } else {
                dependencies.withSpacePinnedShortcutGroup(
                    spaceId,
                    pin.folderId
                ) { pins in
                    pins.removeAll { $0.id == pin.id }
                    pins.insert(
                        pin,
                        at: max(0, min(pin.index, pins.count))
                    )
                }
            }
        }
    }

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
            destinationValidator: ShortcutPinDestinationValidator(
                spaceExists: { [weak tabManager] spaceId in
                    tabManager?.spaceStateOwner.contains(spaceId: spaceId)
                        ?? false
                },
                folderSpaceId: { [weak tabManager] folderId in
                    tabManager?.folderCollectionStateOwner.spaceId(
                        for: folderId
                    )
                }
            ),
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
            folderOpenState: tabManager.folderOpenState,
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
