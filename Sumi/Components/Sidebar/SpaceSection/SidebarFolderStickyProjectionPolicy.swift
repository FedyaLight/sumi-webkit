//
//  SidebarFolderStickyProjectionPolicy.swift
//  Sumi
//

import Foundation

/// Pure transition rules for a collapsed folder's window-local sticky item
/// set (Zen-style: only items the user was on at collapse time, or activated
/// while collapsed, stay visible outside the folder).
enum SidebarFolderStickyProjectionPolicy {
    struct Context {
        let isFolderOpen: Bool
        /// Depth-first positional order of all descendant launcher pins and
        /// split groups (nested folders flattened).
        let orderedDescendantItemIDs: [UUID]
        /// Descendants that can render as a collapsed-projection row right
        /// now: pins with a live tab in this window, plus existing split
        /// groups.
        let visibleEligibleItemIDs: Set<UUID>
        /// The descendant item the window's selection currently points at,
        /// if any: a selected pin, a pin whose live tab is current, or a
        /// split group containing the selection.
        let selectedDescendantItemID: UUID?

        init(
            isFolderOpen: Bool,
            orderedDescendantItemIDs: [UUID],
            visibleEligibleItemIDs: Set<UUID>,
            selectedDescendantItemID: UUID?
        ) {
            self.isFolderOpen = isFolderOpen
            self.orderedDescendantItemIDs = orderedDescendantItemIDs
            self.visibleEligibleItemIDs = visibleEligibleItemIDs
            self.selectedDescendantItemID = selectedDescendantItemID
        }
    }

    /// Sticky seed at the moment of collapse: the selected descendant only.
    static func stickyOnCollapse(context: Context) -> [UUID] {
        guard !context.isFolderOpen,
              let selectedID = context.selectedDescendantItemID else {
            return []
        }
        return [selectedID]
    }

    /// Appends the selected descendant while collapsed. Never removes
    /// entries: switching the selection elsewhere must keep prior sticky
    /// rows visible.
    static func stickyAppendingSelection(
        current: [UUID],
        context: Context
    ) -> [UUID] {
        guard !context.isFolderOpen,
              let selectedID = context.selectedDescendantItemID,
              !current.contains(selectedID) else {
            return current
        }
        return normalized(current + [selectedID], context: context)
    }

    /// Drops entries that left the folder subtree and normalizes to
    /// positional order. An open folder holds no sticky state. Idempotent.
    static func stickyPruned(current: [UUID], context: Context) -> [UUID] {
        guard !context.isFolderOpen else { return [] }
        return normalized(current, context: context)
    }

    /// The rows a collapsed folder actually renders: pruned sticky entries
    /// that are eligible (live pin or existing split group).
    static func visibleStickyIDs(sticky: [UUID], context: Context) -> [UUID] {
        stickyPruned(current: sticky, context: context)
            .filter { context.visibleEligibleItemIDs.contains($0) }
    }

    /// On expand, routes sticky entries still owned by a collapsed
    /// descendant folder to the rootmost collapsed folder in each item's
    /// ancestor chain. Chains run rootmost-first, starting just below the
    /// expanding folder and ending at the item's direct folder.
    static func expandTransfers(
        sticky: [UUID],
        ancestorChainsByItemID: [UUID: [UUID]],
        collapsedFolderIDs: Set<UUID>
    ) -> [UUID: [UUID]] {
        var transfers: [UUID: [UUID]] = [:]
        for itemID in sticky {
            guard let chain = ancestorChainsByItemID[itemID],
                  let target = chain.first(where: collapsedFolderIDs.contains)
            else { continue }
            transfers[target, default: []].append(itemID)
        }
        return transfers
    }

    static func hasActiveProjection(visibleStickyIDs: [UUID]) -> Bool {
        !visibleStickyIDs.isEmpty
    }

    private static func normalized(
        _ sticky: [UUID],
        context: Context
    ) -> [UUID] {
        let members = Set(sticky)
        return context.orderedDescendantItemIDs.filter(members.contains)
    }
}
