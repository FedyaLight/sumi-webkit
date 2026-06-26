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
        case (.splitGroup, .splitGroup(let group)):
            return group.id == operation.scope.sourceItemId
        case (.splitGroup, _):
            return false
        case (.tab, .pin(let pin)):
            return pin.id == operation.scope.sourceItemId
        case (.tab, .tab(let tab)):
            return tab.id == operation.scope.sourceItemId
                || tab.shortcutPinId == operation.scope.sourceItemId
                || shortcutPin(operation.scope.sourceItemId)?.id == tab.shortcutPinId
        case (.tab, .folder),
             (.tab, .splitGroup):
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
        case .splitGroup(let group):
            guard case .spacePinned(let spaceId) = operation.fromContainer else {
                return false
            }
            return group.isShortcutHosted
                && group.hostSpaceId == operation.scope.spaceId
                && group.hostSpaceId == spaceId

        case .folder(let folder):
            switch operation.fromContainer {
            case .spacePinned(let spaceId):
                return folder.spaceId == operation.scope.spaceId
                    && folder.spaceId == spaceId
                    && folder.parentFolderId == nil

            case .folder(let parentFolderId):
                return folder.spaceId == operation.scope.spaceId
                    && folder.parentFolderId == parentFolderId
                    && folderSpaceId(parentFolderId) == operation.scope.spaceId

            default:
                return false
            }

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

        return executeSidebarDragPlan(plan, operation: operation)
    }

    private func executeSidebarDragPlan(
        _ plan: SidebarDragOperationPlan,
        operation: DragOperation
    ) -> Bool {
        switch plan.kind {
        case .folderHeaderReorder(let folder, _),
             .folderHeaderUnsupported(let folder):
            return executeFolderHeaderDragPlan(folder, operation: operation)

        case .shortcutSplitGroup(let group):
            return executeShortcutSplitGroupDragPlan(group, operation: operation)

        case .launcher(let pin, let launcherOperation):
            return executeLauncherDragPlan(
                pin,
                launcherOperation: launcherOperation,
                operation: operation
            )

        case .regularTab(let tab, let regularOperation):
            return executeRegularTabDragPlan(
                tab,
                regularOperation: regularOperation,
                operation: operation
            )

        case .unsupported:
            return false
        }
    }

    private func executeFolderHeaderDragPlan(
        _ folder: TabFolder,
        operation: DragOperation
    ) -> Bool {
        handleFolderDragOperation(folder, operation: operation)
    }

    private func executeShortcutSplitGroupDragPlan(
        _ group: SplitGroup,
        operation: DragOperation
    ) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return moveShortcutHostedSplitGroup(group, in: toSpaceId, to: operation.toIndex)
        default:
            return false
        }
    }

    private func executeLauncherDragPlan(
        _ pin: ShortcutPin,
        launcherOperation _: SidebarLauncherDragOperationKind,
        operation: DragOperation
    ) -> Bool {
        handleShortcutDragOperation(pin, operation: operation)
    }

    private func executeRegularTabDragPlan(
        _ tab: Tab,
        regularOperation: SidebarRegularTabDragOperationKind,
        operation: DragOperation
    ) -> Bool {
        regularTabDragService.execute(
            tab,
            regularOperation: regularOperation,
            dragOperation: operation
        )
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        folderService.alphabetizeFolderPins(folderId, in: spaceId)
    }

    @discardableResult
    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        regularTabDragService.reorderSpacePinnedTabs(tab, in: spaceId, to: index)
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        regularTabDragService.reorderRegularTabs(tab, in: spaceId, to: index)
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

}
