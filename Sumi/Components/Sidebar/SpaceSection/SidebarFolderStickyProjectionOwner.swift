//
//  SidebarFolderStickyProjectionOwner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Applies sticky-projection transitions for one folder in one window,
/// translating view-observed events into coalesced window-local writes.
@MainActor
struct SidebarFolderStickyProjectionOwner {
    let folder: TabFolder
    let presentation: SidebarFolderPresentationCell
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let windowState: BrowserWindowState

    private var coalescer: SidebarFolderProjectionCoalescer {
        windowState.sidebarFolderProjections
    }

    /// The folder just collapsed in this window: sticky becomes the selected
    /// descendant (or nothing).
    func handleCollapse() {
        let context = makeContext(for: folder)
        scheduleTransform(for: folder.id, context: context) { _ in
            SidebarFolderStickyProjectionPolicy.stickyOnCollapse(context: context)
        }
    }

    /// The folder just expanded: entries still owned by a collapsed
    /// descendant folder move to that folder's sticky; the rest dissolve.
    func handleExpand() {
        let sticky = coalescer.pendingOrCurrentProjection(for: folder.id).stickyItemIDs
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: sticky,
            ancestorChainsByItemID: ancestorChains(for: sticky),
            collapsedFolderIDs: collapsedDescendantFolderIDs()
        )
        for (targetFolderID, itemIDs) in transfers {
            guard let targetFolder = inventory.folder(id: targetFolderID) else { continue }
            let targetContext = makeContext(for: targetFolder)
            scheduleTransform(for: targetFolderID, context: targetContext) { current in
                var next = current
                for itemID in itemIDs where !next.contains(itemID) {
                    next.append(itemID)
                }
                return SidebarFolderStickyProjectionPolicy.stickyPruned(
                    current: next,
                    context: targetContext
                )
            }
        }
        coalescer.scheduleMutation(for: folder.id) { _ in .empty }
    }

    /// Selection moved while the folder is collapsed: a descendant the user
    /// selected joins the sticky set. Never removes entries — switching away
    /// must keep prior sticky rows visible.
    func handleSelectionChange() {
        guard !presentation.isExpanded else { return }
        let context = makeContext(for: folder)
        guard context.selectedDescendantItemID != nil else { return }
        scheduleTransform(for: folder.id, context: context) { current in
            SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
                current: current,
                context: context
            )
        }
    }

    /// The folder's descendant set changed (drag in/out, deletion): drop
    /// entries that left, adopt a selected item that just arrived.
    func handleMembershipChange() {
        reconcile()
    }

    /// View (re)mounted: reconcile against the current selection so windows
    /// that never observed the collapse still seed their sticky state.
    func reconcileOnAppear() {
        reconcile()
    }

    /// Render-derived refresh: prune-only, idempotent. Never appends, so the
    /// projection→render→projection loop cannot grow the sticky set.
    func prunePublish() {
        let context = makeContext(for: folder)
        scheduleTransform(for: folder.id, context: context) { current in
            SidebarFolderStickyProjectionPolicy.stickyPruned(
                current: current,
                context: context
            )
        }
    }

    /// A collapsed ancestor stopped owning these projected rows. Preserve
    /// them in this still-collapsed folder before the ancestor expands.
    func adoptStickyItemIDs(_ itemIDs: [UUID]) {
        guard !presentation.isExpanded, !itemIDs.isEmpty else { return }
        let context = makeContext(for: folder)
        scheduleTransform(for: folder.id, context: context) { current in
            SidebarFolderStickyProjectionPolicy.stickyPruned(
                current: current + itemIDs.filter { !current.contains($0) },
                context: context
            )
        }
    }

    private func reconcile() {
        let context = makeContext(for: folder)
        scheduleTransform(for: folder.id, context: context) { current in
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
        for folderID: UUID,
        context: SidebarFolderStickyProjectionPolicy.Context,
        _ transform: @escaping ([UUID]) -> [UUID]
    ) {
        coalescer.scheduleMutation(for: folderID) { state in
            let sticky = transform(state.stickyItemIDs)
            return SidebarFolderProjectionState(
                stickyItemIDs: sticky,
                hasActiveProjection: SidebarFolderStickyProjectionPolicy.hasActiveProjection(
                    visibleStickyIDs: SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
                        sticky: sticky,
                        context: context
                    )
                )
            )
        }
    }

    private func makeContext(
        for contextFolder: TabFolder
    ) -> SidebarFolderStickyProjectionPolicy.Context {
        let descendantItems = inventory.descendantItems(for: contextFolder.id)
        let projectedItems = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: selectionSnapshot,
            windowState: windowState
        ).launcherItems(descendantItems)

        return SidebarFolderStickyProjectionPolicy.Context(
            isFolderOpen: isExpanded(contextFolder),
            orderedDescendantItemIDs: projectedItems.map(\.id),
            visibleEligibleItemIDs: Set(
                projectedItems.lazy.filter(\.isLive).map(\.id)
            ),
            selectedDescendantItemID: projectedItems.first(where: \.isSelected)?.id
        )
    }

    private func ancestorChains(for itemIDs: [UUID]) -> [UUID: [UUID]] {
        var chains: [UUID: [UUID]] = [:]
        for itemID in itemIDs {
            guard let owningFolderID = owningFolderID(of: itemID) else { continue }
            var chain: [UUID] = []
            var currentID: UUID? = owningFolderID
            var visited = Set<UUID>()
            while let folderID = currentID,
                  folderID != folder.id,
                  visited.insert(folderID).inserted {
                chain.append(folderID)
                currentID = inventory.folder(id: folderID)?.parentFolderId
            }
            chains[itemID] = chain.reversed()
        }
        return chains
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

    private func collapsedDescendantFolderIDs() -> Set<UUID> {
        var collapsed = Set<UUID>()
        var visited = Set<UUID>()

        func walk(_ parentID: UUID) {
            guard visited.insert(parentID).inserted else { return }
            for child in inventory.childFoldersByParentID[parentID] ?? [] {
                if !isExpanded(child) {
                    collapsed.insert(child.id)
                }
                walk(child.id)
            }
        }

        walk(folder.id)
        return collapsed
    }

    private func isExpanded(_ contextFolder: TabFolder) -> Bool {
        if contextFolder.id == folder.id {
            return presentation.isExpanded
        }
        return inventory.folderPresentation(id: contextFolder.id)?.isExpanded
            ?? contextFolder.isOpen
    }
}
