import Foundation

@MainActor
enum SidebarDragOperationContextValidator {
    typealias FolderSpaceResolver = (UUID) -> UUID?
    typealias ShortcutPinResolver = (UUID) -> ShortcutPin?

    static func validate(
        operation: DragOperation,
        spaceProfileId: UUID?,
        folderSpaceId: FolderSpaceResolver,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
        operation.fromContainer == operation.scope.sourceContainer
            && scopeProfileMatchesSpace(operation.scope, spaceProfileId: spaceProfileId)
            && operationPayloadMatchesScope(operation, shortcutPin: shortcutPin)
            && sidebarContainer(operation.fromContainer, isIn: operation.scope, folderSpaceId: folderSpaceId)
            && sidebarContainer(operation.toContainer, isIn: operation.scope, folderSpaceId: folderSpaceId)
            && payloadOwnershipMatchesSource(
                operation,
                folderSpaceId: folderSpaceId,
                shortcutPin: shortcutPin
            )
    }

    private static func scopeProfileMatchesSpace(
        _ scope: SidebarDragScope,
        spaceProfileId: UUID?
    ) -> Bool {
        guard let spaceProfileId,
              let scopeProfileId = scope.profileId else {
            return true
        }
        return spaceProfileId == scopeProfileId
    }

    private static func operationPayloadMatchesScope(
        _ operation: DragOperation,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
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
                || shortcutPin(operation.scope.sourceItemId)?.id == tab.shortcutPinId
        case (.tab, .folder):
            return false
        }
    }

    private static func sidebarContainer(
        _ container: TabDragManager.DragContainer,
        isIn scope: SidebarDragScope,
        folderSpaceId: FolderSpaceResolver
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
            return folderSpaceId(folderId) == scope.spaceId
        }
    }

    private static func payloadOwnershipMatchesSource(
        _ operation: DragOperation,
        folderSpaceId: FolderSpaceResolver,
        shortcutPin: ShortcutPinResolver
    ) -> Bool {
        switch operation.payload {
        case .folder(let folder):
            guard case .spacePinned(let spaceId) = operation.fromContainer else {
                return false
            }
            return folder.spaceId == operation.scope.spaceId
                && folder.spaceId == spaceId

        case .pin(let pin):
            return shortcutPinMatchesSource(pin, operation: operation, folderSpaceId: folderSpaceId)

        case .tab(let tab):
            if let shortcutId = tab.shortcutPinId,
               let pin = shortcutPin(shortcutId) {
                return shortcutPinMatchesSource(pin, operation: operation, folderSpaceId: folderSpaceId)
            }

            guard case .spaceRegular(let spaceId) = operation.fromContainer else {
                return false
            }
            return tab.spaceId == operation.scope.spaceId
                && tab.spaceId == spaceId
        }
    }

    private static func shortcutPinMatchesSource(
        _ pin: ShortcutPin,
        operation: DragOperation,
        folderSpaceId: FolderSpaceResolver
    ) -> Bool {
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
                && folderSpaceId(folderId) == operation.scope.spaceId
        default:
            return false
        }
    }
}

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

        let plan = SidebarDragOperationPlanner.plan(
            operation: operation,
            shortcutPin: { shortcutPin(by: $0) }
        )

        switch plan.kind {
        case .folderHeaderReorder(let folder, _),
             .folderHeaderUnsupported(let folder):
            return handleFolderDragOperation(folder, operation: operation)

        case .launcher(let pin, _):
            return handleShortcutDragOperation(pin, operation: operation)

        case .regularTab(let tab, let regularOperation):
            return executeRegularTabSidebarDragOperation(
                regularOperation,
                tab: tab,
                operation: operation
            )

        case .unsupported:
            return false
        }
    }

    private func executeRegularTabSidebarDragOperation(
        _ regularOperation: SidebarRegularTabDragOperationKind,
        tab: Tab,
        operation: DragOperation
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
            didMutate = convertTabToShortcutPin(
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
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = convertTabToShortcutPin(
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
            didMutate = convertTabToShortcutPin(
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
            didMutate = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                at: operation.toIndex,
                openTargetFolder: false
            ) != nil

        case .moveToEssentials where isFolderContainer(operation.fromContainer):
            guard let profileId = resolvedEssentialsProfileId(for: operation) else { return false }
            didMutate = convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex
            ) != nil

        case .moveToPinned(let spaceId) where isFolderContainer(operation.fromContainer):
            didMutate = convertTabToShortcutPin(
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

        case .moveToFolder(let toFolderId) where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard case .spacePinned(let spaceId) = operation.fromContainer else { return false }
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

    private func isFolderContainer(_ container: TabDragManager.DragContainer) -> Bool {
        if case .folder = container {
            return true
        }
        return false
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
        let isCurrentContext = SidebarDragOperationContextValidator.validate(
            operation: operation,
            spaceProfileId: spaces.first(where: { $0.id == operation.scope.spaceId })?.profileId,
            folderSpaceId: { folderSpaceId(for: $0) },
            shortcutPin: { shortcutPin(by: $0) }
        )
        guard isCurrentContext else {
            RuntimeDiagnostics.emit("⚠️ Rejected sidebar drag outside current context: \(operation)")
            return false
        }

        return true
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
