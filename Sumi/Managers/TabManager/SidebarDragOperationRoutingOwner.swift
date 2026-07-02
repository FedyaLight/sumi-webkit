import Foundation

/// Owns sidebar drag operation routing: validates an incoming drag against
/// its declared scope, plans it, and dispatches execution to the folder,
/// split group, launcher, or regular tab owner. Also owns explicit tab moves
/// between spaces triggered from menus.
@MainActor
final class SidebarDragOperationRoutingOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    @discardableResult
    func handleDragOperation(_ operation: DragOperation) -> Bool {
        guard validateSidebarDragOperation(operation) else {
            return false
        }

        let plan = SidebarDragOperationPlanner.plan(
            operation: operation,
            shortcutPin: { tabManager.shortcutPin(by: $0) }
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
            return tabManager.folderMutationOwner.handleFolderDragOperation(folder, operation: operation)

        case .shortcutSplitGroup(let group):
            return executeShortcutSplitGroupDragPlan(group, operation: operation)

        case .launcher(let pin, _):
            return tabManager.handleShortcutDragOperation(pin, operation: operation)

        case .regularTab(let tab, let regularOperation):
            return tabManager.regularTabDragService.execute(
                tab,
                regularOperation: regularOperation,
                dragOperation: operation
            )

        case .unsupported:
            return false
        }
    }

    private func executeShortcutSplitGroupDragPlan(
        _ group: SplitGroup,
        operation: DragOperation
    ) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return tabManager.moveShortcutHostedSplitGroup(group, in: toSpaceId, to: operation.toIndex)
        default:
            return false
        }
    }

    private func validateSidebarDragOperation(_ operation: DragOperation) -> Bool {
        let isCurrentContext = SidebarDragOperationContextValidator.validate(
            operation: operation,
            spaceProfileId: tabManager.spaces
                .first(where: { $0.id == operation.scope.spaceId })?.profileId,
            folderSpaceId: { tabManager.folderSpaceId(for: $0) },
            shortcutPin: { tabManager.shortcutPin(by: $0) }
        )
        guard isCurrentContext else {
            RuntimeDiagnostics.emit("⚠️ Rejected sidebar drag outside current context: \(operation)")
            return false
        }

        return true
    }

    // MARK: - Explicit Tab Moves

    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            guard let tab = tabManager.tab(for: tabId),
                  let currentSpaceId = tab.spaceId,
                  currentSpaceId != targetSpaceId else {
                return
            }

            let targetTabs = tabManager.regularTabCollectionOwner.tabs(in: targetSpaceId)
            moveTabBetweenSpaces(
                tab,
                to: targetSpaceId,
                asSpacePinned: false,
                toIndex: targetTabs.count
            )
        }
    }

    private func moveTabBetweenSpaces(
        _ tab: Tab,
        to toSpaceId: UUID,
        asSpacePinned: Bool,
        toIndex: Int
    ) {
        if asSpacePinned {
            _ = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: toSpaceId,
                folderId: nil,
                at: toIndex
            )
            return
        }

        tabManager.removeFromCurrentContainer(tab)
        tabManager.regularTabCollectionOwner.insert(tab, in: toSpaceId, at: toIndex)
        tabManager.scheduleStructuralPersistence()
    }
}
