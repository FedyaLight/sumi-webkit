import Foundation
import SumiDomain

/// Applies the same sticky-row rules as folders to a Space's pinned root.
@MainActor
struct SidebarSpacePinnedStickyProjectionOwner {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let windowState: BrowserWindowState

    private var state: SidebarSpacePinnedCollapseState {
        windowState.sidebarSpacePinnedCollapse
    }

    var visibleStickyItemIDs: [UUID] {
        let context = makeContext()
        let current = state.pendingOrCurrentProjection(for: space.id).stickyItemIDs
        let reconciled = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: SidebarFolderStickyProjectionPolicy.stickyPruned(
                current: current,
                context: context
            ),
            context: context
        )
        return SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
            sticky: reconciled,
            context: context
        )
    }

    func handleCollapse() {
        let context = makeContext()
        scheduleTransform(context: context) { _ in
            SidebarFolderStickyProjectionPolicy.stickyOnCollapse(context: context)
        }
    }

    func handleExpand() {
        let sticky = state.pendingOrCurrentProjection(for: space.id).stickyItemIDs
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: sticky,
            ancestorChainsByItemID: ancestorChains(for: sticky),
            collapsedFolderIDs: Set(
                inventory.foldersByID.values.filter { !$0.isOpen }.map(\.id)
            )
        )
        for (folderID, itemIDs) in transfers {
            guard let folder = inventory.folder(id: folderID) else { continue }
            SidebarFolderStickyProjectionOwner(
                folder: folder,
                inventory: inventory,
                selection: selection,
                selectionSnapshot: selectionSnapshot,
                windowState: windowState
            ).adoptStickyItemIDs(itemIDs)
        }
        state.scheduleMutation(for: space.id) { _ in .empty }
    }

    func handleSelectionChange() {
        guard state.isCollapsed(space.id) else { return }
        reconcile()
    }

    func handleMembershipChange() {
        reconcile()
    }

    func reconcileOnAppear() {
        reconcile()
    }

    private func reconcile() {
        let context = makeContext()
        scheduleTransform(context: context) { current in
            SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
                current: SidebarFolderStickyProjectionPolicy.stickyPruned(
                    current: current,
                    context: context
                ),
                context: context
            )
        }
    }

    private func scheduleTransform(
        context: SidebarFolderStickyProjectionPolicy.Context,
        _ transform: @escaping ([UUID]) -> [UUID]
    ) {
        state.scheduleMutation(for: space.id) { projection in
            let sticky = transform(projection.stickyItemIDs)
            let visible = SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
                sticky: sticky,
                context: context
            )
            return SidebarFolderProjectionState(
                stickyItemIDs: sticky,
                hasActiveProjection: !visible.isEmpty
            )
        }
    }

    private func makeContext() -> SidebarFolderStickyProjectionPolicy.Context {
        let leafItems = inventory.orderedPinnedLeafItems()
        let projectedItems = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: selectionSnapshot,
            windowState: windowState
        ).launcherItems(leafItems)

        return SidebarFolderStickyProjectionPolicy.Context(
            isFolderOpen: !state.isCollapsed(space.id),
            orderedDescendantItemIDs: projectedItems.map(\.id),
            visibleEligibleItemIDs: Set(
                projectedItems.lazy.filter(\.isLive).map(\.id)
            ),
            selectedDescendantItemID: projectedItems.first(where: \.isSelected)?.id
        )
    }

    private func ancestorChains(for itemIDs: [UUID]) -> [UUID: [UUID]] {
        var result: [UUID: [UUID]] = [:]
        for itemID in itemIDs {
            guard let ownerID = owningFolderID(of: itemID) else { continue }
            var chain: [UUID] = []
            var currentID: UUID? = ownerID
            var visited = Set<UUID>()
            while let folderID = currentID, visited.insert(folderID).inserted {
                chain.append(folderID)
                currentID = inventory.folder(id: folderID)?.parentFolderId
            }
            result[itemID] = chain.reversed()
        }
        return result
    }

    private func owningFolderID(of itemID: UUID) -> UUID? {
        if let pin = inventory.pin(id: itemID) {
            return pin.folderId
        }
        if let group = inventory.splitGroup(id: itemID),
           case .shortcutSidebar(_, _, let folderID, _) = group.container {
            return folderID
        }
        return nil
    }
}
