import Foundation

@MainActor
extension TabManager {
    @discardableResult
    func performSidebarDragOperation(_ operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            handleDragOperation(operation)
        }
    }

    @discardableResult
    func handleDragOperation(_ operation: DragOperation) -> Bool {
        guard validateSidebarDragOperation(operation) else {
            return false
        }

        if let folder = operation.folder {
            return handleFolderDragOperation(folder, operation: operation)
        }

        if let pin = operation.pin {
            return handleShortcutDragOperation(pin, operation: operation)
        }

        guard let tab = operation.tab else { return false }

        if let shortcutId = tab.shortcutPinId,
           let pin = shortcutPin(by: shortcutId) {
            return handleShortcutDragOperation(pin, operation: operation)
        }

        var didMutate = false
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            didMutate = reorderGlobalPinnedTabs(tab, to: operation.toIndex)

        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            didMutate = reorderSpacePinnedTabs(tab, in: toSpaceId, to: operation.toIndex)

        case (.spaceRegular(let fromSpaceId), .spaceRegular(let toSpaceId)) where fromSpaceId == toSpaceId:
            didMutate = reorderRegularTabs(tab, in: toSpaceId, to: operation.toIndex)

        case (.spaceRegular, .spacePinned(let targetSpaceId)):
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case (.spacePinned, .spaceRegular(let targetSpaceId)):
            didMutate = moveTabIntoRegularSection(tab, spaceId: targetSpaceId, index: operation.toIndex)

        case (.spaceRegular, .essentials), (.spacePinned, .essentials):
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case (.essentials, .spaceRegular(let spaceId)):
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case (.essentials, .spacePinned(let spaceId)):
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case (.folder(let fromFolderId), .folder(let toFolderId)):
            guard let spaceId = tab.spaceId else { return false }
            let targetFolderId = fromFolderId == toFolderId ? fromFolderId : toFolderId
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case (.folder, .essentials):
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case (.folder, .spacePinned(let spaceId)):
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case (.folder, .spaceRegular(let spaceId)):
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case (.spaceRegular(let spaceId), .folder(let toFolderId)):
            guard let targetSpaceId = folderSpaceId(for: toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case (.spacePinned(let spaceId), .folder(let toFolderId)):
            guard let targetSpaceId = folderSpaceId(for: toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case (.essentials, .folder),
             (.spacePinned, .spacePinned),
             (.spaceRegular, .spaceRegular),
             (.none, _),
             (_, .none):
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
            return false
        }

        if didMutate {
            dissolveActiveSplitIfNeeded(for: tab)
        }
        return didMutate
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        folderService.alphabetizeFolderPins(folderId, in: spaceId)
    }

    @discardableResult
    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        if let shortcutId = tab.shortcutPinId,
           let pin = shortcutPin(by: shortcutId) {
            return reorderSpacePinned(pin, in: spaceId, to: index)
        }

        return convertTabToShortcutPin(
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
        withStructuralUpdateTransaction {
            guard var regularTabs = tabsBySpace[spaceId],
                  let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
                return false
            }
            let adjustedIndex = adjustedSameContainerInsertionIndex(
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

            setTabs(regularTabs, for: spaceId)
            scheduleStructuralPersistence()
            return true
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

    @discardableResult
    private func handleFolderDragOperation(_ folder: TabFolder, operation: DragOperation) -> Bool {
        folderService.handleFolderDragOperation(folder, operation: operation)
    }

    @discardableResult
    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) -> Bool {
        withStructuralUpdateTransaction {
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(by: shortcutId),
                  let profileId = pin.profileId else {
                return false
            }
            var pins = pinnedByProfile[profileId] ?? []
            guard let currentIndex = pins.firstIndex(where: { $0.id == pin.id }) else { return false }
            guard index != currentIndex else { return false }

            pins.remove(at: currentIndex)
            let safeIndex = max(0, min(index, pins.count))
            pins.insert(pin, at: safeIndex)
            setPinnedTabs(reindexed(pins), for: profileId)
            scheduleStructuralPersistence()
            return true
        }
    }

    private func moveTabIntoRegularSection(_ tab: Tab, spaceId: UUID, index: Int) -> Bool {
        removeFromCurrentContainer(tab)
        tab.folderId = nil
        tab.spaceId = spaceId
        tab.isSpacePinned = false
        tab.isPinned = false

        var regularTabs = tabsBySpace[spaceId] ?? []
        let safeIndex = max(0, min(index, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)
        for (index, existingTab) in regularTabs.enumerated() {
            existingTab.index = index
        }
        setTabs(regularTabs, for: spaceId)
        scheduleStructuralPersistence()
        return true
    }

    private func validateSidebarDragOperation(_ operation: DragOperation) -> Bool {
        guard operation.fromContainer == operation.scope.sourceContainer,
              scopeProfileMatchesSpace(operation.scope),
              operationPayloadMatchesScope(operation),
              sidebarContainer(operation.fromContainer, isIn: operation.scope),
              sidebarContainer(operation.toContainer, isIn: operation.scope),
              payloadOwnershipMatchesSource(operation)
        else {
            RuntimeDiagnostics.emit("⚠️ Rejected sidebar drag outside current context: \(operation)")
            return false
        }

        return true
    }

    private func scopeProfileMatchesSpace(_ scope: SidebarDragScope) -> Bool {
        guard let spaceProfileId = spaces.first(where: { $0.id == scope.spaceId })?.profileId,
              let scopeProfileId = scope.profileId else {
            return true
        }
        return spaceProfileId == scopeProfileId
    }

    private func operationPayloadMatchesScope(_ operation: DragOperation) -> Bool {
        switch (operation.scope.sourceItemKind, operation.payload) {
        case (.folder, .folder(let folder)):
            return folder.id == operation.scope.sourceItemId
        case (.folder, _):
            return false
        case (.tab, .pin(let pin)):
            return pin.id == operation.scope.sourceItemId
        case (.tab, .tab(let tab)):
            return tab.id == operation.scope.sourceItemId
                || tab.shortcutPinId == operation.scope.sourceItemId
        case (.tab, .folder):
            return false
        }
    }

    private func sidebarContainer(
        _ container: TabDragManager.DragContainer,
        isIn scope: SidebarDragScope
    ) -> Bool {
        switch container {
        case .none:
            return false
        case .essentials:
            return scope.profileId != nil
        case .spacePinned(let spaceId),
             .spaceRegular(let spaceId):
            return spaceId == scope.spaceId
        case .folder(let folderId):
            return folderSpaceId(for: folderId) == scope.spaceId
        }
    }

    private func payloadOwnershipMatchesSource(_ operation: DragOperation) -> Bool {
        switch operation.payload {
        case .folder(let folder):
            guard case .spacePinned(let spaceId) = operation.fromContainer else {
                return false
            }
            return folder.spaceId == operation.scope.spaceId
                && folder.spaceId == spaceId

        case .pin(let pin):
            return shortcutPinMatchesSource(pin, operation: operation)

        case .tab(let tab):
            if let shortcutId = tab.shortcutPinId,
               let pin = shortcutPin(by: shortcutId) {
                return shortcutPinMatchesSource(pin, operation: operation)
            }

            guard case .spaceRegular(let spaceId) = operation.fromContainer else {
                return false
            }
            return tab.spaceId == operation.scope.spaceId
                && tab.spaceId == spaceId
        }
    }

    private func shortcutPinMatchesSource(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        switch (pin.role, operation.fromContainer) {
        case (.essential, .essentials):
            return pin.profileId == operation.scope.profileId
        case (.spacePinned, .spacePinned(let spaceId)):
            return pin.spaceId == operation.scope.spaceId
                && pin.spaceId == spaceId
                && pin.folderId == nil
        case (.spacePinned, .folder(let folderId)):
            return pin.spaceId == operation.scope.spaceId
                && pin.folderId == folderId
                && folderSpaceId(for: folderId) == operation.scope.spaceId
        default:
            return false
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
