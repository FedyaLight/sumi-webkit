import Foundation

@MainActor
final class SidebarRegularTabDragService {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    @discardableResult
    func execute(
        _ tab: Tab,
        regularOperation: SidebarRegularTabDragOperationKind,
        dragOperation operation: DragOperation
    ) -> Bool {
        var didMutate = false
        switch regularOperation {
        case .reorder where operation.toContainer == .essentials:
            didMutate = reorderGlobalPinnedTabs(tab, to: operation.toIndex)

        case .reorder(let spaceId) where operation.toContainer == .spacePinned(spaceId):
            didMutate = reorderSpacePinnedTabs(tab, in: spaceId, to: operation.toIndex)

        case .reorder(let spaceId) where operation.toContainer == .spaceRegular(spaceId):
            didMutate = reorderRegularTabs(tab, in: spaceId, to: operation.toIndex)

        case .moveToPinned(let targetSpaceId) where operation.fromContainer == .spaceRegular(operation.scope.spaceId):
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToRegular(let targetSpaceId) where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            didMutate = moveTabIntoRegularSection(tab, spaceId: targetSpaceId, index: operation.toIndex)

        case .moveToEssentials
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId)
                || operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard let profileId = tabManager.resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToRegular(let spaceId) where operation.fromContainer == .essentials:
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case .moveToPinned(let spaceId) where operation.fromContainer == .essentials:
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToFolder(let toFolderId) where isFolderContainer(operation.fromContainer):
            guard let spaceId = tab.spaceId else { return false }
            guard case .folder(let fromFolderId) = operation.fromContainer else { return false }
            let targetFolderId = fromFolderId == toFolderId ? fromFolderId : toFolderId
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case .moveToEssentials where isFolderContainer(operation.fromContainer):
            guard let profileId = tabManager.resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToPinned(let spaceId) where isFolderContainer(operation.fromContainer):
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToRegular(let spaceId) where isFolderContainer(operation.fromContainer):
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case .moveToFolder(let toFolderId) where operation.fromContainer == .spaceRegular(operation.scope.spaceId):
            guard case .spaceRegular(let spaceId) = operation.fromContainer else { return false }
            guard let targetSpaceId = tabManager.folderSpaceId(for: toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case .moveToFolder(let toFolderId) where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard case .spacePinned(let spaceId) = operation.fromContainer else { return false }
            guard let targetSpaceId = tabManager.folderSpaceId(for: toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case .unsupported,
             .reorder,
             .moveToPinned,
             .moveToFolder,
             .moveToEssentials,
             .moveToRegular:
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
            return false
        }

        if didMutate {
            dissolveActiveSplitIfNeeded(for: tab)
        }
        return didMutate
    }

    @discardableResult
    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        if let shortcutId = tab.shortcutPinId,
           let pin = tabManager.shortcutPin(by: shortcutId) {
            return tabManager.reorderSpacePinned(pin, in: spaceId, to: index)
        }

        return tabManager.convertTabToShortcutPin(
            tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            folderId: nil,
            at: index
        ) != nil
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            guard var regularTabs = tabManager.tabsBySpace[spaceId],
                  let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
                return false
            }
            let adjustedIndex = tabManager.adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: index
            )
            guard adjustedIndex != currentIndex else { return false }

            regularTabs.remove(at: currentIndex)
            let clampedIndex = min(max(adjustedIndex, 0), regularTabs.count)
            regularTabs.insert(tab, at: clampedIndex)

            for (index, regularTab) in regularTabs.enumerated() {
                regularTab.index = index
            }

            tabManager.setTabs(regularTabs, for: spaceId)
            tabManager.scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            guard let shortcutId = tab.shortcutPinId,
                  let pin = tabManager.shortcutPin(by: shortcutId),
                  let profileId = pin.profileId else {
                return false
            }
            var pins = tabManager.pinnedByProfile[profileId] ?? []
            guard let currentIndex = pins.firstIndex(where: { $0.id == pin.id }) else { return false }
            guard index != currentIndex else { return false }

            pins.remove(at: currentIndex)
            let safeIndex = max(0, min(index, pins.count))
            pins.insert(pin, at: safeIndex)
            tabManager.setPinnedTabs(tabManager.reindexed(pins), for: profileId)
            tabManager.scheduleStructuralPersistence()
            return true
        }
    }

    private func moveTabIntoRegularSection(_ tab: Tab, spaceId: UUID, index: Int) -> Bool {
        tabManager.removeFromCurrentContainer(tab)
        tab.folderId = nil
        tab.spaceId = spaceId
        tab.isSpacePinned = false
        tab.isPinned = false

        var regularTabs = tabManager.tabsBySpace[spaceId] ?? []
        let safeIndex = max(0, min(index, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)
        for (index, existingTab) in regularTabs.enumerated() {
            existingTab.index = index
        }
        tabManager.setTabs(regularTabs, for: spaceId)
        tabManager.scheduleStructuralPersistence()
        return true
    }

    private func isFolderContainer(_ container: TabDragManager.DragContainer) -> Bool {
        if case .folder = container {
            return true
        }
        return false
    }

    private func dissolveActiveSplitIfNeeded(for tab: Tab) {
        guard !tab.isShortcutLiveInstance else { return }
        guard let splitManager = tabManager.browserManager?.splitManager,
              let browserManager = tabManager.browserManager,
              let windows = browserManager.windowRegistry?.windows else {
            return
        }

        for (windowId, _) in windows where splitManager.visibleTabIds(for: windowId).contains(tab.id) {
            splitManager.handleTabClosure(tab.id)
        }
    }
}
