import AppKit
import Foundation

@MainActor
final class TabFolderService {
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
            guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }

            let folder = folders[index]
            RuntimeDiagnostics.emit("   Found folder '\(folder.name)' in space \(spaceId.uuidString.prefix(8))...")

            var movedTabsCount = 0
            for tab in tabManager.allTabs() where tab.folderId == folderId {
                tab.folderId = nil
                tab.isSpacePinned = true
                movedTabsCount += 1
            }
            tabManager.markRegularTabsStructurallyDirty(for: spaceId)

            let existingPins = tabManager.spacePinnedPins(for: spaceId)
            if existingPins.isEmpty == false {
                let movedPins = existingPins.filter { $0.folderId == folderId }.map(\.id)
                let detachedPins = existingPins.map { pin -> ShortcutPin in
                    guard pin.folderId == folderId else { return pin }
                    movedTabsCount += 1
                    return pin.moved(toFolderId: nil)
                }
                let reindexedPins = tabManager.normalizedSpacePinnedShortcuts(detachedPins)
                tabManager.setSpacePinnedShortcuts(reindexedPins, for: spaceId)
                for pinId in movedPins {
                    if let updatedPin = reindexedPins.first(where: { $0.id == pinId }) {
                        tabManager.updateTransientShortcutBindings(for: updatedPin)
                    }
                }
            }

            RuntimeDiagnostics.emit("   Moved \(movedTabsCount) tabs out of folder")

            folders.remove(at: index)
            tabManager.setFolders(folders, for: spaceId)
            tabManager.applyTopLevelSpacePinnedOrder(
                tabManager.topLevelSpacePinnedItems(for: spaceId),
                for: spaceId
            )

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

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            guard let targetFolder = tabManager.folder(by: folderId) else { return }

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
}
