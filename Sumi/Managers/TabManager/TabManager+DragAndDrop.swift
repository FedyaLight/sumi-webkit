import Foundation

@MainActor
extension TabManager {
    func performSidebarDragOperation(_ operation: DragOperation) {
        withStructuralUpdateTransaction {
            handleDragOperation(operation)
        }
    }

    func handleDragOperation(_ operation: DragOperation) {
        if let folder = operation.folder {
            handleFolderDragOperation(folder, operation: operation)
            return
        }

        if let pin = operation.pin {
            handleShortcutDragOperation(pin, operation: operation)
            return
        }

        guard let tab = operation.tab else { return }

        if let shortcutId = tab.shortcutPinId,
           let pin = shortcutPin(by: shortcutId) {
            handleShortcutDragOperation(pin, operation: operation)
            return
        }

        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            reorderGlobalPinnedTabs(tab, to: operation.toIndex)

        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)):
            if fromSpaceId == toSpaceId {
                reorderSpacePinnedTabs(tab, in: toSpaceId, to: operation.toIndex)
            } else {
                _ = convertTabToShortcutPin(
                    tab,
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: toSpaceId,
                    folderId: nil,
                    at: operation.toIndex
                )
            }

        case (.spaceRegular(let fromSpaceId), .spaceRegular(let toSpaceId)):
            if fromSpaceId == toSpaceId {
                reorderRegularTabs(tab, in: toSpaceId, to: operation.toIndex)
            } else {
                moveTabBetweenSpaces(
                    tab,
                    from: fromSpaceId,
                    to: toSpaceId,
                    asSpacePinned: false,
                    toIndex: operation.toIndex
                )
            }

        case (.spaceRegular, .spacePinned(let targetSpaceId)):
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                at: operation.toIndex
            )

        case (.spacePinned, .spaceRegular(let targetSpaceId)):
            removeFromCurrentContainer(tab)
            tab.folderId = nil
            tab.spaceId = targetSpaceId
            tab.isSpacePinned = false
            var regularTabs = tabsBySpace[targetSpaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, regularTabs.count))
            regularTabs.insert(tab, at: safeIndex)
            for (index, existingTab) in regularTabs.enumerated() {
                existingTab.index = index
            }
            setTabs(regularTabs, for: targetSpaceId)
            scheduleStructuralPersistence()

        case (.spaceRegular, .essentials), (.spacePinned, .essentials):
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return }
            _ = convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            )

        case (.essentials, .spaceRegular(let spaceId)):
            removeFromCurrentContainer(tab)
            tab.folderId = nil
            tab.isSpacePinned = false
            tab.spaceId = spaceId
            var regularTabs = tabsBySpace[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, regularTabs.count))
            regularTabs.insert(tab, at: safeIndex)
            for (index, existingTab) in regularTabs.enumerated() {
                existingTab.index = index
            }
            setTabs(regularTabs, for: spaceId)
            scheduleStructuralPersistence()

        case (.essentials, .spacePinned(let spaceId)):
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            )

        case (.folder(let fromFolderId), .folder(let toFolderId)):
            guard let spaceId = tab.spaceId else { return }
            let targetFolderId = fromFolderId == toFolderId ? fromFolderId : toFolderId
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            )

        case (.folder, .essentials):
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return }
            _ = convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            )

        case (.folder, .spacePinned(let spaceId)):
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            )

        case (.folder, .spaceRegular(let spaceId)):
            removeFromCurrentContainer(tab)
            tab.folderId = nil
            tab.spaceId = spaceId
            tab.isSpacePinned = false
            var regularTabs = tabsBySpace[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, regularTabs.count))
            regularTabs.insert(tab, at: safeIndex)
            for (index, existingTab) in regularTabs.enumerated() {
                existingTab.index = index
            }
            setTabs(regularTabs, for: spaceId)
            scheduleStructuralPersistence()

        case (.spaceRegular(let spaceId), .folder(let toFolderId)):
            let targetSpaceId = folderSpaceId(for: toFolderId) ?? spaceId
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            )

        case (.spacePinned(let spaceId), .folder(let toFolderId)):
            let targetSpaceId = folderSpaceId(for: toFolderId) ?? spaceId
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            )

        case (.essentials, .folder):
            RuntimeDiagnostics.emit("⚠️ Cannot move global pinned tabs to folders")
            return

        case (.none, _), (_, .none):
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
        }

        dissolveActiveSplitIfNeeded(for: tab)
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        folderService.alphabetizeFolderPins(folderId, in: spaceId)
    }

    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        if let shortcutId = tab.shortcutPinId,
           let pin = shortcutPin(by: shortcutId) {
            reorderSpacePinned(pin, in: spaceId, to: index)
            return
        }

        _ = convertTabToShortcutPin(
            tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            folderId: nil,
            at: index
        )
    }

    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        withStructuralUpdateTransaction {
            guard var regularTabs = tabsBySpace[spaceId],
                  let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
                return
            }
            guard index != currentIndex else { return }

            regularTabs.remove(at: currentIndex)
            let adjustedIndex = currentIndex < index ? index - 1 : index
            let clampedIndex = min(max(adjustedIndex, 0), regularTabs.count)
            regularTabs.insert(tab, at: clampedIndex)

            for (index, regularTab) in regularTabs.enumerated() {
                regularTab.index = index
            }

            setTabs(regularTabs, for: spaceId)
            scheduleStructuralPersistence()
        }
    }

    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        withStructuralUpdateTransaction {
            guard let tab = tab(for: tabId),
                  let currentSpaceId = tab.spaceId,
                  currentSpaceId != targetSpaceId else {
                return
            }

            let targetTabs = tabsBySpace[targetSpaceId] ?? []
            moveTabBetweenSpaces(
                tab,
                from: currentSpaceId,
                to: targetSpaceId,
                asSpacePinned: false,
                toIndex: targetTabs.count
            )
        }
    }

    func moveTabUp(_ tabId: UUID) {
        withStructuralUpdateTransaction {
            guard let spaceId = findSpaceForTab(tabId) else { return }
            let tabs = tabsBySpace[spaceId] ?? []
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }
            guard currentIndex > 0 else { return }

            let tab = tabs[currentIndex]
            let targetTab = tabs[currentIndex - 1]
            let tempIndex = tab.index
            tab.index = targetTab.index
            targetTab.index = tempIndex

            setTabs(tabs, for: spaceId)
            scheduleStructuralPersistence()
        }
    }

    func moveTabDown(_ tabId: UUID) {
        withStructuralUpdateTransaction {
            guard let spaceId = findSpaceForTab(tabId) else { return }
            let tabs = tabsBySpace[spaceId] ?? []
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }
            guard currentIndex < tabs.count - 1 else { return }

            let tab = tabs[currentIndex]
            let targetTab = tabs[currentIndex + 1]
            let tempIndex = tab.index
            tab.index = targetTab.index
            targetTab.index = tempIndex

            setTabs(tabs, for: spaceId)
            scheduleStructuralPersistence()
        }
    }

    private func handleFolderDragOperation(_ folder: TabFolder, operation: DragOperation) {
        folderService.handleFolderDragOperation(folder, operation: operation)
    }

    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) {
        withStructuralUpdateTransaction {
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(by: shortcutId),
                  let profileId = pin.profileId else {
                return
            }
            var pins = pinnedByProfile[profileId] ?? []
            guard let currentIndex = pins.firstIndex(where: { $0.id == pin.id }) else { return }
            guard index != currentIndex else { return }

            pins.remove(at: currentIndex)
            let adjustedIndex = currentIndex < index ? index - 1 : index
            let safeIndex = max(0, min(adjustedIndex, pins.count))
            pins.insert(pin, at: safeIndex)
            setPinnedTabs(reindexed(pins), for: profileId)
            scheduleStructuralPersistence()
        }
    }

    private func moveTabBetweenSpaces(
        _ tab: Tab,
        from _: UUID,
        to toSpaceId: UUID,
        asSpacePinned: Bool,
        toIndex: Int
    ) {
        if asSpacePinned {
            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: toSpaceId,
                folderId: nil,
                at: toIndex
            )
            return
        }

        removeFromCurrentContainer(tab)
        tab.spaceId = toSpaceId

        var regularTabs = tabsBySpace[toSpaceId] ?? []
        tab.index = toIndex
        let safeIndex = max(0, min(toIndex, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)

        for (index, regularTab) in regularTabs.enumerated() {
            regularTab.index = index
        }

        setTabs(regularTabs, for: toSpaceId)
        scheduleStructuralPersistence()
    }

    private func findSpaceForTab(_ tabId: UUID) -> UUID? {
        for (spaceId, tabs) in tabsBySpace where tabs.contains(where: { $0.id == tabId }) {
            return spaceId
        }
        return nil
    }

    private func dissolveActiveSplitIfNeeded(for tab: Tab) {
        guard let splitManager = browserManager?.splitManager,
              let browserManager,
              let windows = browserManager.windowRegistry?.windows else {
            return
        }

        for (windowId, _) in windows where splitManager.isSplit(for: windowId) {
            if splitManager.leftTabId(for: windowId) == tab.id {
                splitManager.exitSplit(keep: .right, for: windowId)
            } else if splitManager.rightTabId(for: windowId) == tab.id {
                splitManager.exitSplit(keep: .left, for: windowId)
            }
        }
    }
}
