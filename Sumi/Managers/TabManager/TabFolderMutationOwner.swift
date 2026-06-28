import AppKit
import Foundation

@MainActor
final class TabFolderMutationOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        return tabManager.withStructuralUpdateTransaction {
            RuntimeDiagnostics.emit("📁 Creating folder for spaceId: \(spaceId.uuidString)")
            let folder = TabFolder(
                name: name,
                spaceId: spaceId,
                color: tabManager.spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor
            )
            folder.index = tabManager.topLevelSpacePinnedItems(for: spaceId).count
            RuntimeDiagnostics.emit("   Created folder: \(folder.name) (id: \(folder.id.uuidString.prefix(8))...)")

            var folders = tabManager.folders(for: spaceId)
            folders.append(folder)
            tabManager.setFolders(folders, for: spaceId)

            tabManager.scheduleStructuralPersistence()
            return folder
        }
    }

    @discardableResult
    func createFolder(
        for spaceId: UUID,
        parentFolderId: UUID?,
        name: String = "New Folder"
    ) -> TabFolder? {
        tabManager.withStructuralUpdateTransaction {
            if let parentFolderId {
                guard tabManager.folderSpaceId(for: parentFolderId) == spaceId else {
                    return nil
                }
            }

            let folder = TabFolder(
                name: name,
                spaceId: spaceId,
                parentFolderId: parentFolderId,
                color: tabManager.spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor,
                index: childItems(in: parentFolderId, spaceId: spaceId).count
            )

            var folders = tabManager.folders(for: spaceId)
            folders.append(folder)
            tabManager.setFolders(folders, for: spaceId)
            tabManager.scheduleStructuralPersistence()
            return folder
        }
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        guard let folder = tabManager.folder(by: folderId) else { return }
        folder.name = newName
        tabManager.markFoldersStructurallyDirty(for: folder.spaceId)
        tabManager.requestStructuralPublish()
        tabManager.scheduleStructuralPersistence()
    }

    func updateFolderIcon(_ folderId: UUID, icon: String) {
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let folder = tabManager.folder(by: folderId) else { return }

        folder.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(trimmedIcon)
        tabManager.markFoldersStructurallyDirty(for: folder.spaceId)
        tabManager.requestStructuralPublish()
        tabManager.scheduleStructuralPersistence()
    }

    func setFolder(_ folderId: UUID, open isOpen: Bool) {
        tabManager.withStructuralUpdateTransaction {
            guard let folder = tabManager.folder(by: folderId),
                  folder.isOpen != isOpen else {
                return
            }

            folder.isOpen = isOpen
            tabManager.markFoldersStructurallyDirty(for: folder.spaceId)
            tabManager.requestStructuralPublish()
            tabManager.scheduleStructuralPersistence()
        }
    }

    func toggleFolderOpenState(_ folderId: UUID) {
        guard let folder = tabManager.folder(by: folderId) else { return }
        setFolder(folderId, open: !folder.isOpen)
    }

    func deleteFolder(_ folderId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            RuntimeDiagnostics.emit("🗑️ Deleting folder: \(folderId.uuidString)")

            guard let spaceId = tabManager.folderSpaceId(for: folderId) else { return }
            var folders = tabManager.folders(for: spaceId)
            guard let folder = folders.first(where: { $0.id == folderId }) else { return }

            let deletedFolderIds = descendantFolderIds(including: folder.id, spaceId: spaceId)
            let parentFolderId = folder.parentFolderId
            let existingPins = tabManager.spacePinnedShortcuts[spaceId] ?? []
            let deletedPins = existingPins.filter { pin in
                guard let pinFolderId = pin.folderId else { return false }
                return deletedFolderIds.contains(pinFolderId)
            }
            let deletedPinIds = Set(deletedPins.map(\.id))
            let liveTabsToRemove = tabManager.allTabs()
                .filter { tab in
                    guard let tabFolderId = tab.folderId,
                          deletedFolderIds.contains(tabFolderId) else {
                        return false
                    }
                    return tab.shortcutPinId.map { deletedPinIds.contains($0) == false } ?? true
                }
                .map(\.id)

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
            tabManager.setFolders(folders, for: spaceId)
            applyChildItems(parentItems, in: parentFolderId, spaceId: spaceId)

            let remainingPins = existingPins.filter { pin in
                guard let pinFolderId = pin.folderId else { return true }
                return deletedFolderIds.contains(pinFolderId) == false
            }
            tabManager.setSpacePinnedShortcuts(
                tabManager.normalizedSpacePinnedShortcuts(remainingPins),
                for: spaceId
            )

            for pin in deletedPins {
                tabManager.runtimeContext?.captureDeletedShortcutLauncher(pin)
                let liveWindowIds = tabManager.transientShortcutTabsByWindow.compactMap { windowId, tabsByPin in
                    tabsByPin[pin.id] == nil ? nil : windowId
                }
                for windowId in liveWindowIds {
                    tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)
                }
                tabManager.runtimeContext?.forEachWindowState { windowState in
                    windowState.removeFromShortcutLiveSelectionHistory(pin.id)
                }
            }

            for tabId in liveTabsToRemove {
                tabManager.removeTab(tabId)
            }

            tabManager.runtimeContext?.deleteLiveFolderState(forFolderIds: deletedFolderIds)
            tabManager.scheduleStructuralPersistence()
        }
    }

    func ungroupFolder(_ folderId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            RuntimeDiagnostics.emit("🗂️ Ungrouping folder: \(folderId.uuidString)")

            guard let spaceId = tabManager.folderSpaceId(for: folderId) else { return }
            var folders = tabManager.folders(for: spaceId)
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
            tabManager.setFolders(folders, for: spaceId)
            applyChildItems(parentItems, in: parentFolderId, spaceId: spaceId)

            var movedLiveTabsCount = 0
            for tab in tabManager.allTabs() where tab.folderId == folderId {
                tab.folderId = parentFolderId
                tab.isSpacePinned = true
                movedLiveTabsCount += 1
            }
            if movedLiveTabsCount > 0 {
                tabManager.markRegularTabsStructurallyDirty(for: spaceId)
            }

            tabManager.runtimeContext?.deleteLiveFolderState(forFolderIds: [folderId])
            tabManager.scheduleStructuralPersistence()
        }
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        (tabManager.foldersBySpace[spaceId] ?? []).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func setAllFolders(open isOpen: Bool, in spaceId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            let folders = tabManager.foldersBySpace[spaceId] ?? []
            guard folders.isEmpty == false else { return }

            var didChange = false
            for folder in folders where folder.isOpen != isOpen {
                folder.isOpen = isOpen
                didChange = true
            }

            if didChange {
                tabManager.markFoldersStructurallyDirty(for: spaceId)
                tabManager.requestStructuralPublish()
                tabManager.scheduleStructuralPersistence()
            }
        }
    }

    func openFolderIfNeeded(_ folderId: UUID) {
        setFolder(folderId, open: true)
    }

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            guard let targetFolder = tabManager.folder(by: folderId) else { return }
            guard tabManager.runtimeContext?.isLiveFolder(folderId) != true else { return }

            targetFolder.isOpen = true
            tabManager.markFoldersStructurallyDirty(for: targetFolder.spaceId)
            let targetIndex = tabManager.folderPinnedPins(for: folderId, in: targetFolder.spaceId).count

            if let shortcutId = tab.shortcutPinId,
               let pin = tabManager.shortcutPin(by: shortcutId)
            {
                _ = tabManager.moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetFolder.spaceId,
                    folderId: folderId,
                    index: targetIndex
                )
                return
            }

            _ = tabManager.convertTabToShortcutPin(
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
            return tabManager.reorderFolderInTopLevelPinned(folder, in: toSpaceId, to: operation.toIndex)
        case (.spacePinned(let fromSpaceId), .folder(let targetFolderId)) where fromSpaceId == folder.spaceId:
            guard tabManager.runtimeContext?.isLiveFolder(targetFolderId) != true else {
                return false
            }
            guard let targetSpaceId = tabManager.folderSpaceId(for: targetFolderId),
                  targetSpaceId == folder.spaceId else {
                return false
            }
            return moveFolder(folder, toParentFolderId: targetFolderId, in: targetSpaceId, to: operation.toIndex)
        case (.folder(let sourceParentId), .spacePinned(let toSpaceId)) where toSpaceId == folder.spaceId:
            guard folder.parentFolderId == sourceParentId else { return false }
            return moveFolder(folder, toParentFolderId: nil, in: toSpaceId, to: operation.toIndex)
        case (.folder(let sourceParentId), .folder(let targetFolderId)):
            guard folder.parentFolderId == sourceParentId,
                  tabManager.runtimeContext?.isLiveFolder(targetFolderId) != true,
                  let targetSpaceId = tabManager.folderSpaceId(for: targetFolderId),
                  targetSpaceId == folder.spaceId else {
                return false
            }
            return moveFolder(folder, toParentFolderId: targetFolderId, in: targetSpaceId, to: operation.toIndex)
        default:
            return false
        }
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            let folderPins = tabManager.spacePinnedPins(for: spaceId)
                .filter { $0.folderId == folderId }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            guard !folderPins.isEmpty else { return }
            tabManager.withSpacePinnedShortcutGroup(for: spaceId, folderId: folderId) { pins in
                pins = folderPins
            }
            tabManager.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func moveFolder(
        _ folder: TabFolder,
        toParentFolderId parentFolderId: UUID?,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            if let parentFolderId {
                guard tabManager.folderSpaceId(for: parentFolderId) == spaceId else {
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
                    tabManager.adjustedSameContainerInsertionIndex(
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
            tabManager.scheduleStructuralPersistence()
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
        let folders = tabManager.childFolders(of: parentFolderId, in: spaceId)
            .map { ($0.index, 0, FolderContainerItem.folder($0.id)) }
        let pins = tabManager.spacePinnedPins(for: spaceId)
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
        let folders = tabManager.foldersBySpace[spaceId] ?? []
        let folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let pinMap = Dictionary(uniqueKeysWithValues: (tabManager.spacePinnedShortcuts[spaceId] ?? []).map { ($0.id, $0) })

        var touchedPinIds: Set<UUID> = []
        var rebuiltPins = tabManager.spacePinnedShortcuts[spaceId] ?? []

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

        tabManager.setFolders(folders, for: spaceId)
        let normalizedPins = tabManager.normalizedSpacePinnedShortcuts(rebuiltPins)
        tabManager.setSpacePinnedShortcuts(normalizedPins, for: spaceId)
        for pinId in touchedPinIds {
            if let updatedPin = normalizedPins.first(where: { $0.id == pinId }) {
                tabManager.updateTransientShortcutBindings(for: updatedPin)
            }
        }
    }

    private func isFolder(_ folderId: UUID?, descendantOf ancestorId: UUID, in spaceId: UUID) -> Bool {
        guard let folderId else { return false }
        var currentId: UUID? = folderId
        var seen: Set<UUID> = []
        while let id = currentId {
            guard seen.insert(id).inserted else { return true }
            guard let folder = (tabManager.foldersBySpace[spaceId] ?? []).first(where: { $0.id == id }) else {
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
        let folders = tabManager.foldersBySpace[spaceId] ?? []
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
