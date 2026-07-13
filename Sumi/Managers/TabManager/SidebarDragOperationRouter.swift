import Foundation
import SumiDomain

/// Routes sidebar drag operations: validates an incoming drag against
/// its declared scope, plans it, and dispatches execution to the folder,
/// split group, launcher, or regular tab owner. Also owns explicit tab moves
/// between spaces triggered from menus.
@MainActor
final class SidebarDragOperationRouter {
    struct Dependencies {
        let withStructuralUpdateTransaction: (@MainActor () -> Bool) -> Bool
        let shortcutPin: (UUID) -> ShortcutPin?
        let handleFolderDragOperation: (TabFolder, DragOperation) -> Bool
        let handleShortcutDragOperation: (ShortcutPin, DragOperation) -> Bool
        let executeRegularTabDrag: (Tab, SidebarRegularTabDragOperationKind, DragOperation) -> Bool
        let tab: (UUID) -> Tab?
        let dragProxyTab: (ShortcutPin) -> Tab
        let folder: (UUID) -> TabFolder?
        let splitGroup: (UUID) -> SplitGroup?
        let moveShortcutHostedSplitGroup: (SplitGroup, UUID, Int) -> Bool
        let profileIdForSpace: (UUID) -> UUID?
        let folderSpaceId: (UUID) -> UUID?
        let regularTabs: (UUID) -> [Tab]
        let convertTabToShortcutPin: (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int) -> ShortcutPin?
        let removeFromCurrentContainer: (Tab) -> Void
        let insertRegularTab: (Tab, UUID, Int) -> Void
        let scheduleStructuralPersistence: () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func performSidebarDragOperation(_ operation: DragOperation) -> Bool {
        dependencies.withStructuralUpdateTransaction {
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
            shortcutPin: dependencies.shortcutPin
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
            return dependencies.handleFolderDragOperation(folder, operation)

        case .shortcutSplitGroup(let group):
            return executeShortcutSplitGroupDragPlan(group, operation: operation)

        case .launcher(let pin, _):
            return dependencies.handleShortcutDragOperation(pin, operation)

        case .regularTab(let tab, let regularOperation):
            return dependencies.executeRegularTabDrag(
                tab,
                regularOperation,
                operation
            )

        case .unsupported:
            return false
        }
    }

    func resolveDragTab(for id: UUID) -> Tab? {
        if let live = dependencies.tab(id) {
            return live
        }
        if let pin = dependencies.shortcutPin(id) {
            return dependencies.dragProxyTab(pin)
        }
        return nil
    }

    func resolveDragTab(for item: SumiDragItem) -> Tab? {
        guard item.splitMemberID != nil else {
            return resolveDragTab(for: item.tabId)
        }
        guard let memberID = validatedMemberID(for: item) else {
            return nil
        }
        switch memberID {
        case .regularTab(let tabID):
            return dependencies.tab(tabID)
        case .shortcutPin(let pinID):
            guard let pin = dependencies.shortcutPin(pinID) else {
                return nil
            }
            return dependencies.dragProxyTab(pin)
        }
    }

    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload? {
        if item.splitMemberID != nil {
            guard let memberID = validatedMemberID(for: item) else {
                return nil
            }
            switch memberID {
            case .regularTab(let tabID):
                return dependencies.tab(tabID).map(DragOperation.Payload.tab)
            case .shortcutPin(let pinID):
                return dependencies.shortcutPin(pinID).map(DragOperation.Payload.pin)
            }
        }

        switch item.kind {
        case .tab:
            if let pin = dependencies.shortcutPin(item.tabId) {
                return .pin(pin)
            }
            return resolveDragTab(for: item.tabId).map { .tab($0) }
        case .folder:
            return dependencies.folder(item.tabId).map { .folder($0) }
        case .splitGroup:
            return dependencies.splitGroup(item.tabId).map { .splitGroup($0) }
        }
    }

    private func validatedMemberID(
        for item: SumiDragItem
    ) -> SplitMemberID? {
        guard let memberID = item.splitMemberID else { return nil }
        guard let groupID = item.splitGroupID else { return memberID }
        guard dependencies.splitGroup(groupID)?.contains(memberID) == true else {
            return nil
        }
        return memberID
    }

    private func executeShortcutSplitGroupDragPlan(
        _ group: SplitGroup,
        operation: DragOperation
    ) -> Bool {
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return dependencies.moveShortcutHostedSplitGroup(group, toSpaceId, operation.toIndex)
        default:
            return false
        }
    }

    private func validateSidebarDragOperation(_ operation: DragOperation) -> Bool {
        let isCurrentContext = SidebarDragOperationContextValidator.validate(
            operation: operation,
            spaceProfileId: dependencies.profileIdForSpace(operation.scope.spaceId),
            folderSpaceId: dependencies.folderSpaceId,
            shortcutPin: dependencies.shortcutPin
        )
        guard isCurrentContext else {
            RuntimeDiagnostics.emit("⚠️ Rejected sidebar drag outside current context: \(operation)")
            return false
        }

        return true
    }

    // MARK: - Explicit Tab Moves

    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        _ = dependencies.withStructuralUpdateTransaction {
            guard let tab = dependencies.tab(tabId),
                  let currentSpaceId = tab.spaceId,
                  currentSpaceId != targetSpaceId else {
                return false
            }

            let targetTabs = dependencies.regularTabs(targetSpaceId)
            moveTabBetweenSpaces(
                tab,
                to: targetSpaceId,
                asSpacePinned: false,
                toIndex: targetTabs.count
            )
            return true
        }
    }

    private func moveTabBetweenSpaces(
        _ tab: Tab,
        to toSpaceId: UUID,
        asSpacePinned: Bool,
        toIndex: Int
    ) {
        if asSpacePinned {
            _ = dependencies.convertTabToShortcutPin(
                tab,
                .spacePinned,
                nil,
                toSpaceId,
                nil,
                toIndex
            )
            return
        }

        dependencies.removeFromCurrentContainer(tab)
        dependencies.insertRegularTab(tab, toSpaceId, toIndex)
        dependencies.scheduleStructuralPersistence()
    }
}

extension SidebarDragOperationRouter.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return false }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            shortcutPin: { [weak tabManager] id in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: id)
            },
            handleFolderDragOperation: { [weak tabManager] folder, operation in
                tabManager?.folderMutationOwner.handleFolderDragOperation(folder, operation: operation) ?? false
            },
            handleShortcutDragOperation: { [weak tabManager] pin, operation in
                guard let tabManager else { return false }
                return tabManager.structuralLookupCoordinator.withTransaction {
                    tabManager.shortcutDragOperationOwner.handleShortcutDragOperation(pin, operation: operation)
                }
            },
            executeRegularTabDrag: { [weak tabManager] tab, regularOperation, dragOperation in
                tabManager?.regularTabDragService.execute(
                    tab,
                    regularOperation: regularOperation,
                    dragOperation: dragOperation
                ) ?? false
            },
            tab: { [weak tabManager] id in
                tabManager?.tabCollectionMembershipOwner.tab(for: id)
            },
            dragProxyTab: { [weak tabManager] pin in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.shortcutPresentationOwner.dragProxyTab(for: pin)
            },
            folder: { [weak tabManager] id in
                tabManager?.folderCollectionStateOwner.folder(by: id)
            },
            splitGroup: { [weak tabManager] id in
                tabManager?.splitGroupStore.group(id: id)
            },
            moveShortcutHostedSplitGroup: { [weak tabManager] group, spaceId, index in
                tabManager?.splitGroupSidebarOrdering.moveGroup(
                    group,
                    in: spaceId,
                    to: index
                ) ?? false
            },
            profileIdForSpace: { [weak tabManager] spaceId in
                tabManager?.spaceStateOwner.profileId(for: spaceId)
            },
            folderSpaceId: { [weak tabManager] folderId in
                tabManager?.folderCollectionStateOwner.spaceId(for: folderId)
            },
            regularTabs: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            convertTabToShortcutPin: { [weak tabManager] tab, role, profileId, spaceId, folderId, index in
                tabManager?.shortcutPinCommandOwner.convertTabToShortcutPin(
                    tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    at: index
                )
            },
            removeFromCurrentContainer: { [weak tabManager] tab in
                tabManager?.shortcutContainerRemovalOwner.removeFromCurrentContainer(tab)
            },
            insertRegularTab: { [weak tabManager] tab, spaceId, index in
                tabManager?.regularTabCollectionOwner.insert(tab, in: spaceId, at: index)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            }
        )
    }
}
