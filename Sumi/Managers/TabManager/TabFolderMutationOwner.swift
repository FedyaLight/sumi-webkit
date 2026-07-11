import AppKit
import Foundation

@MainActor
final class TabFolderMutationOwner {
    struct Dependencies {
        let withStructuralUpdateTransactionFolder: @MainActor (@MainActor () -> TabFolder) -> TabFolder
        let withStructuralUpdateTransactionOptionalFolder: @MainActor (@MainActor () -> TabFolder?) -> TabFolder?
        let withStructuralUpdateTransactionBool: @MainActor (@MainActor () -> Bool) -> Bool
        let withStructuralUpdateTransactionVoid: @MainActor (@MainActor () -> Void) -> Void
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let spacePinnedStructureOwner: SpacePinnedStructureOwner
        let folderCollectionStateOwner: TabFolderCollectionStateOwner
        let structuralCollectionMutationOwner: TabStructuralCollectionMutationOwner
        let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
        let tabCollectionMembershipOwner: TabCollectionMembershipOwner
        let shortcutTabBindings: ShortcutTabBindingSynchronizer
        let shortcutLiveTabRetirement: ShortcutLiveTabRetirementService
        let tabRemovalOwner: TabRemovalOwner
        let shortcutPinCommandOwner: ShortcutPinCommandOwner
        let runtimePorts: @MainActor () -> RuntimePortRegistry?
        let markFoldersStructurallyDirty: @MainActor (UUID) -> Void
        let markRegularTabsStructurallyDirty: @MainActor (UUID) -> Void
        let requestStructuralPublish: @MainActor () -> Void
        let scheduleStructuralPersistence: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        dependencies.withStructuralUpdateTransactionFolder {
            RuntimeDiagnostics.emit("📁 Creating folder for spaceId: \(spaceId.uuidString)")
            let folder = TabFolder(
                name: name,
                spaceId: spaceId,
                color: dependencies.spaceStateOwner.spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor
            )
            folder.index = dependencies.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId).count
            RuntimeDiagnostics.emit("   Created folder: \(folder.name) (id: \(folder.id.uuidString.prefix(8))...)")

            var folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            folders.append(folder)
            dependencies.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)

            dependencies.scheduleStructuralPersistence()
            return folder
        }
    }

    @discardableResult
    func createFolder(
        for spaceId: UUID,
        parentFolderId: UUID?,
        name: String = "New Folder"
    ) -> TabFolder? {
        dependencies.withStructuralUpdateTransactionOptionalFolder {
            if let parentFolderId {
                guard dependencies.folderCollectionStateOwner.spaceId(for: parentFolderId) == spaceId else {
                    return nil
                }
            }

            let folder = TabFolder(
                name: name,
                spaceId: spaceId,
                parentFolderId: parentFolderId,
                color: dependencies.spaceStateOwner.spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor,
                index: childItems(in: parentFolderId, spaceId: spaceId).count
            )

            var folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            folders.append(folder)
            dependencies.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
            dependencies.scheduleStructuralPersistence()
            return folder
        }
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        guard let folder = dependencies.folderCollectionStateOwner.folder(by: folderId) else { return }
        folder.name = newName
        dependencies.markFoldersStructurallyDirty(folder.spaceId)
        dependencies.requestStructuralPublish()
        dependencies.scheduleStructuralPersistence()
    }

    func updateFolderIcon(_ folderId: UUID, icon: String) {
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let folder = dependencies.folderCollectionStateOwner.folder(by: folderId) else { return }

        folder.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(trimmedIcon)
        dependencies.markFoldersStructurallyDirty(folder.spaceId)
        dependencies.requestStructuralPublish()
        dependencies.scheduleStructuralPersistence()
    }

    func setFolder(_ folderId: UUID, open isOpen: Bool) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard let folder = dependencies.folderCollectionStateOwner.folder(by: folderId),
                  folder.isOpen != isOpen else {
                return
            }

            folder.isOpen = isOpen
            dependencies.markFoldersStructurallyDirty(folder.spaceId)
            dependencies.requestStructuralPublish()
            dependencies.scheduleStructuralPersistence()
        }
    }

    func toggleFolderOpenState(_ folderId: UUID) {
        guard let folder = dependencies.folderCollectionStateOwner.folder(by: folderId) else { return }
        setFolder(folderId, open: !folder.isOpen)
    }

    func deleteFolder(_ folderId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            RuntimeDiagnostics.emit("🗑️ Deleting folder: \(folderId.uuidString)")

            guard let spaceId = dependencies.folderCollectionStateOwner.spaceId(for: folderId) else { return }
            var folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            guard let folder = folders.first(where: { $0.id == folderId }) else { return }

            let deletedFolderIds = descendantFolderIds(including: folder.id, spaceId: spaceId)
            let parentFolderId = folder.parentFolderId
            let existingPins = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
            let deletedPins = existingPins.filter { pin in
                guard let pinFolderId = pin.folderId else { return false }
                return deletedFolderIds.contains(pinFolderId)
            }
            let deletedPinIds = Set(deletedPins.map(\.id))
            let liveTabsToRemove = dependencies.tabCollectionMembershipOwner.allTabs()
                .filter { tab in
                    guard let tabFolderId = tab.folderId,
                          deletedFolderIds.contains(tabFolderId) else {
                        return false
                    }
                    return tab.shortcutPinId.map { deletedPinIds.contains($0) == false } ?? true
                }
                .map(\.id)
            guard let retirement = dependencies.shortcutLiveTabRetirement
                .prepareDeletedPinRetirements(deletedPinIds) else {
                return
            }

            var parentItems = childItems(in: parentFolderId, spaceId: spaceId)
            parentItems.removeAll { item in
                switch item {
                case .folder(let childFolderId):
                    return deletedFolderIds.contains(childFolderId)
                case .shortcut(let pinId):
                    return deletedPinIds.contains(pinId)
                }
            }

            folders.removeAll { deletedFolderIds.contains($0.id) }
            dependencies.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
            applyChildItems(parentItems, in: parentFolderId, spaceId: spaceId)

            let remainingPins = existingPins.filter { pin in
                guard let pinFolderId = pin.folderId else { return true }
                return deletedFolderIds.contains(pinFolderId) == false
            }
            dependencies.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
                dependencies.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(remainingPins),
                for: spaceId
            )

            for pin in deletedPins {
                dependencies.runtimePorts()?.captureDeletedShortcutLauncher(pin)
            }

            for tabId in liveTabsToRemove {
                dependencies.tabRemovalOwner.removeTab(tabId)
            }

            dependencies.shortcutLiveTabRetirement
                .finishAfterCurrentBatch(retirement)
            dependencies.runtimePorts()?.deleteLiveFolderState(forFolderIds: deletedFolderIds)
            dependencies.scheduleStructuralPersistence()
        }
    }

    func ungroupFolder(_ folderId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            RuntimeDiagnostics.emit("🗂️ Ungrouping folder: \(folderId.uuidString)")

            guard let spaceId = dependencies.folderCollectionStateOwner.spaceId(for: folderId) else { return }
            var folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }

            let folder = folders[index]
            let parentFolderId = folder.parentFolderId
            let liftedItems = childItems(in: folder.id, spaceId: spaceId)
            var parentItems = childItems(in: parentFolderId, spaceId: spaceId)
            if let folderItemIndex = parentItems.firstIndex(of: .folder(folder.id)) {
                parentItems.remove(at: folderItemIndex)
                parentItems.insert(contentsOf: liftedItems, at: folderItemIndex)
            } else {
                parentItems.append(contentsOf: liftedItems)
            }

            folders.remove(at: index)
            dependencies.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
            applyChildItems(parentItems, in: parentFolderId, spaceId: spaceId)

            var movedLiveTabsCount = 0
            for tab in dependencies.tabCollectionMembershipOwner.allTabs() where tab.folderId == folderId {
                tab.folderId = parentFolderId
                tab.isSpacePinned = true
                movedLiveTabsCount += 1
            }
            if movedLiveTabsCount > 0 {
                dependencies.markRegularTabsStructurallyDirty(spaceId)
            }

            dependencies.runtimePorts()?.deleteLiveFolderState(forFolderIds: [folderId])
            dependencies.scheduleStructuralPersistence()
        }
    }

    func setAllFolders(open isOpen: Bool, in spaceId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            let folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            guard folders.isEmpty == false else { return }

            var didChange = false
            for folder in folders where folder.isOpen != isOpen {
                folder.isOpen = isOpen
                didChange = true
            }

            if didChange {
                dependencies.markFoldersStructurallyDirty(spaceId)
                dependencies.requestStructuralPublish()
                dependencies.scheduleStructuralPersistence()
            }
        }
    }

    func openFolderIfNeeded(_ folderId: UUID) {
        setFolder(folderId, open: true)
    }

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard let targetFolder = dependencies.folderCollectionStateOwner.folder(by: folderId) else { return }
            guard dependencies.runtimePorts()?.isLiveFolder(folderId) != true else { return }

            targetFolder.isOpen = true
            dependencies.markFoldersStructurallyDirty(targetFolder.spaceId)
            let targetIndex = dependencies.shortcutPinCollectionStateOwner.folderPinnedPins(for: folderId, in: targetFolder.spaceId).count

            if let shortcutId = tab.shortcutPinId,
               let pin = dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutId) {
                _ = dependencies.shortcutPinCommandOwner.moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetFolder.spaceId,
                    folderId: folderId,
                    index: targetIndex
                )
                return
            }

            _ = dependencies.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                at: targetIndex
            )
        }
    }

    @discardableResult
    func handleFolderDragOperation(_ folder: TabFolder, operation: DragOperation) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return dependencies.spacePinnedStructureOwner.reorderFolderInTopLevelPinned(folder, in: toSpaceId, to: operation.toIndex)
        case (.spacePinned(let fromSpaceId), .folder(let targetFolderId)) where fromSpaceId == folder.spaceId:
            guard dependencies.runtimePorts()?.isLiveFolder(targetFolderId) != true else {
                return false
            }
            guard let targetSpaceId = dependencies.folderCollectionStateOwner.spaceId(for: targetFolderId),
                  targetSpaceId == folder.spaceId else {
                return false
            }
            return moveFolder(folder, toParentFolderId: targetFolderId, in: targetSpaceId, to: operation.toIndex)
        case (.folder(let sourceParentId), .spacePinned(let toSpaceId)) where toSpaceId == folder.spaceId:
            guard folder.parentFolderId == sourceParentId else { return false }
            return moveFolder(folder, toParentFolderId: nil, in: toSpaceId, to: operation.toIndex)
        case (.folder(let sourceParentId), .folder(let targetFolderId)):
            guard folder.parentFolderId == sourceParentId,
                  dependencies.runtimePorts()?.isLiveFolder(targetFolderId) != true,
                  let targetSpaceId = dependencies.folderCollectionStateOwner.spaceId(for: targetFolderId),
                  targetSpaceId == folder.spaceId else {
                return false
            }
            return moveFolder(folder, toParentFolderId: targetFolderId, in: targetSpaceId, to: operation.toIndex)
        default:
            return false
        }
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            let folderPins = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
                .filter { $0.folderId == folderId }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            guard !folderPins.isEmpty else { return }
            dependencies.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: folderId) { pins in
                pins = folderPins
            }
            dependencies.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func moveFolder(
        _ folder: TabFolder,
        toParentFolderId parentFolderId: UUID?,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> Bool {
        dependencies.withStructuralUpdateTransactionBool {
            if let parentFolderId {
                guard dependencies.folderCollectionStateOwner.spaceId(for: parentFolderId) == spaceId else {
                    return false
                }
            }
            guard folder.spaceId == spaceId,
                  parentFolderId != folder.id,
                  !isFolder(parentFolderId, descendantOf: folder.id, in: spaceId) else {
                return false
            }

            let sourceParentId = folder.parentFolderId
            var sourceItems = childItems(in: sourceParentId, spaceId: spaceId)
            let sourceIndex = sourceItems.firstIndex(of: .folder(folder.id))
            if let sourceIndex {
                sourceItems.remove(at: sourceIndex)
            }

            var targetItems: [FolderContainerItem]
            let adjustedIndex: Int
            if sourceParentId == parentFolderId {
                targetItems = sourceItems
                adjustedIndex = sourceIndex.map {
                    dependencies.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                        currentIndex: $0,
                        proposedIndex: targetIndex
                    )
                } ?? targetIndex
            } else {
                applyChildItems(sourceItems, in: sourceParentId, spaceId: spaceId)
                targetItems = childItems(in: parentFolderId, spaceId: spaceId)
                adjustedIndex = targetIndex
            }

            let safeIndex = max(0, min(adjustedIndex, targetItems.count))
            targetItems.insert(.folder(folder.id), at: safeIndex)
            applyChildItems(targetItems, in: parentFolderId, spaceId: spaceId)

            if let parentFolderId {
                openFolderIfNeeded(parentFolderId)
            }
            dependencies.scheduleStructuralPersistence()
            return true
        }
    }

    private enum FolderContainerItem: Hashable {
        case folder(UUID)
        case shortcut(UUID)

        var id: UUID {
            switch self {
            case .folder(let id), .shortcut(let id):
                return id
            }
        }
    }

    private func childItems(in parentFolderId: UUID?, spaceId: UUID) -> [FolderContainerItem] {
        let folders = dependencies.folderCollectionStateOwner.childFolders(of: parentFolderId, in: spaceId)
            .map { ($0.index, 0, FolderContainerItem.folder($0.id)) }
        let pins = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
            .filter { $0.folderId == parentFolderId }
            .map { ($0.index, 1, FolderContainerItem.shortcut($0.id)) }

        return (folders + pins)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2.id.uuidString < rhs.2.id.uuidString
            }
            .map(\.2)
    }

    private func applyChildItems(
        _ items: [FolderContainerItem],
        in parentFolderId: UUID?,
        spaceId: UUID
    ) {
        let folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
        let folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let pinMap = Dictionary(uniqueKeysWithValues: dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).map { ($0.id, $0) })

        var touchedPinIds: Set<UUID> = []
        var rebuiltPins = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)

        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folderId):
                guard let folder = folderMap[folderId] else { continue }
                folder.spaceId = spaceId
                folder.parentFolderId = parentFolderId
                folder.index = index

            case .shortcut(let pinId):
                guard let pin = pinMap[pinId] else { continue }
                touchedPinIds.insert(pin.id)
                let updated = pin
                    .refreshed(index: index)
                    .moved(toFolderId: parentFolderId)
                if let existingIndex = rebuiltPins.firstIndex(where: { $0.id == pin.id }) {
                    rebuiltPins[existingIndex] = updated
                } else {
                    rebuiltPins.append(updated)
                }
            }
        }

        dependencies.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
        let normalizedPins = dependencies.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(rebuiltPins)
        dependencies.structuralCollectionMutationOwner.setSpacePinnedShortcuts(normalizedPins, for: spaceId)
        for pinId in touchedPinIds {
            if let updatedPin = normalizedPins.first(where: { $0.id == pinId }) {
                dependencies.shortcutTabBindings.refreshInstances(for: updatedPin)
            }
        }
    }

    private func isFolder(_ folderId: UUID?, descendantOf ancestorId: UUID, in spaceId: UUID) -> Bool {
        guard let folderId else { return false }
        var currentId: UUID? = folderId
        var seen: Set<UUID> = []
        while let id = currentId {
            guard seen.insert(id).inserted else { return true }
            guard let folder = dependencies.folderCollectionStateOwner.folders(for: spaceId).first(where: { $0.id == id }) else {
                return false
            }
            if folder.parentFolderId == ancestorId {
                return true
            }
            currentId = folder.parentFolderId
        }
        return false
    }

    private func descendantFolderIds(including rootFolderId: UUID, spaceId: UUID) -> Set<UUID> {
        let folders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
        let childrenByParentId = Dictionary(grouping: folders, by: \.parentFolderId)

        var result: Set<UUID> = []
        var stack = [rootFolderId]
        while let folderId = stack.popLast() {
            guard result.insert(folderId).inserted else { continue }
            stack.append(contentsOf: (childrenByParentId[folderId] ?? []).map(\.id))
        }
        return result
    }
}

extension TabFolderMutationOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransactionFolder: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionOptionalFolder: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionBool: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            spaceStateOwner: tabManager.spaceStateOwner,
            spacePinnedStructureOwner: tabManager.spacePinnedStructureOwner,
            folderCollectionStateOwner: tabManager.folderCollectionStateOwner,
            structuralCollectionMutationOwner: tabManager.structuralCollectionMutationOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            tabCollectionMembershipOwner: tabManager.tabCollectionMembershipOwner,
            shortcutTabBindings: tabManager.shortcutTabBindings,
            shortcutLiveTabRetirement: tabManager.shortcutLiveTabRetirement,
            tabRemovalOwner: tabManager.tabRemovalOwner,
            shortcutPinCommandOwner: tabManager.shortcutPinCommandOwner,
            runtimePorts: { [weak tabManager] in
                tabManager?.runtimePorts
            },
            markFoldersStructurallyDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markFoldersStructurallyDirty(for: spaceId)
            },
            markRegularTabsStructurallyDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markRegularTabsStructurallyDirty(for: spaceId)
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.requestPublish()
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            }
        )
    }
}
