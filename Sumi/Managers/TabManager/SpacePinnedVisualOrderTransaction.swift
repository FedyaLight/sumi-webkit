import Foundation
import SumiDomain

/// Atomically places visual rows in top-level Pinned and folder containers.
/// A shortcut-backed split group always occupies one position.
@MainActor
final class SpacePinnedVisualOrderTransaction {
    private let ordering: SplitGroupSidebarOrderingService
    private let groupMutations: SplitGroupMutationService
    private let orderTransaction: SpacePinnedOrderTransaction

    init(
        ordering: SplitGroupSidebarOrderingService,
        groupMutations: SplitGroupMutationService,
        orderTransaction: SpacePinnedOrderTransaction
    ) {
        self.ordering = ordering
        self.groupMutations = groupMutations
        self.orderTransaction = orderTransaction
    }

    func reorder(
        _ movingItem: SplitGroupVisualListItem,
        in spaceID: UUID,
        to proposedIndex: Int
    ) -> Bool {
        let currentItems = ordering.topLevelItems(for: spaceID)
        guard let currentIndex = currentItems.firstIndex(of: movingItem) else {
            return false
        }
        let targetIndex = SpacePinnedShortcutOrderOwner
            .adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: proposedIndex
            )
        guard targetIndex != currentIndex else { return false }

        var reorderedItems = currentItems
        let moving = reorderedItems.remove(at: currentIndex)
        reorderedItems.insert(
            moving,
            at: max(0, min(targetIndex, reorderedItems.count))
        )

        return apply(reorderedItems, in: spaceID)
    }

    func moveFolder(
        _ folderID: UUID,
        in spaceID: UUID,
        from sourceFolderID: UUID?,
        to targetFolderID: UUID?,
        at presentedBoundary: Int
    ) -> Bool {
        var sourceItems = items(in: spaceID, folderID: sourceFolderID)
        guard let sourceIndex = sourceItems.firstIndex(of: .folder(folderID)) else {
            return false
        }

        if sourceFolderID == targetFolderID {
            let targetIndex = SpacePinnedShortcutOrderOwner
                .adjustedSameContainerInsertionIndex(
                    currentIndex: sourceIndex,
                    proposedIndex: presentedBoundary
                )
            guard targetIndex != sourceIndex else { return false }
            let moving = sourceItems.remove(at: sourceIndex)
            sourceItems.insert(
                moving,
                at: max(0, min(targetIndex, sourceItems.count))
            )
            return apply(
                [.init(folderID: sourceFolderID, items: sourceItems)],
                in: spaceID
            )
        }

        let moving = sourceItems.remove(at: sourceIndex)
        var targetItems = items(in: spaceID, folderID: targetFolderID)
        targetItems.insert(
            moving,
            at: max(0, min(presentedBoundary, targetItems.count))
        )
        return apply(
            [
                .init(folderID: sourceFolderID, items: sourceItems),
                .init(folderID: targetFolderID, items: targetItems),
            ],
            in: spaceID
        )
    }

    /// Finalizes the requested visual position inside the enclosing catalog
    /// mutation; ordering and the caller's side effect commit atomically.
    func placeExisting(
        _ movingItem: SplitGroupVisualListItem,
        in spaceID: UUID,
        at targetIndex: Int,
        applying sideEffect: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        let currentItems = ordering.topLevelItems(for: spaceID)
        guard let currentIndex = currentItems.firstIndex(of: movingItem) else {
            return false
        }
        let safeTarget = max(0, min(targetIndex, currentItems.count - 1))
        guard currentIndex != safeTarget else { return sideEffect() }
        let proposedBoundary = safeTarget + (currentIndex < safeTarget ? 1 : 0)
        var reorderedItems = currentItems
        let moving = reorderedItems.remove(at: currentIndex)
        reorderedItems.insert(
            moving,
            at: max(0, min(
                SpacePinnedShortcutOrderOwner.adjustedSameContainerInsertionIndex(
                    currentIndex: currentIndex,
                    proposedIndex: proposedBoundary
                ),
                reorderedItems.count
            ))
        )
        return apply(reorderedItems, in: spaceID, applying: sideEffect)
    }

    private func apply(
        _ reorderedItems: [SplitGroupVisualListItem],
        in spaceID: UUID
    ) -> Bool {
        apply(reorderedItems, in: spaceID, applying: { true })
    }

    private func apply(
        _ orders: [SpacePinnedOrderTransaction.VisualContainerOrder],
        in spaceID: UUID
    ) -> Bool {
        let currentGroups = ordering.groupsSnapshot
        guard let planned = orderTransaction.planVisualOrders(
            orders,
            in: spaceID,
            groups: currentGroups
        ) else { return false }
        return commit(planned, expectedGroups: currentGroups)
    }

    private func items(
        in spaceID: UUID,
        folderID: UUID?
    ) -> [SplitGroupVisualListItem] {
        let resolver = ordering.resolver(for: spaceID)
        return folderID.map(resolver.folderItems(for:))
            ?? resolver.topLevelItems()
    }

    private func apply(
        _ reorderedItems: [SplitGroupVisualListItem],
        in spaceID: UUID,
        applying sideEffect: @escaping @MainActor () -> Bool
    ) -> Bool {
        let currentGroups = ordering.groupsSnapshot
        guard let planned = orderTransaction.planVisualOrder(
            reorderedItems,
            in: spaceID,
            groups: currentGroups
        ) else { return false }

        return commit(
            planned,
            expectedGroups: currentGroups,
            applying: sideEffect
        )
    }

    private func commit(
        _ planned: (plan: SpacePinnedOrderTransaction.Plan, groups: [SplitGroup]),
        expectedGroups currentGroups: [SplitGroup],
        applying sideEffect: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        if planned.groups == currentGroups {
            guard orderTransaction.apply(planned.plan), sideEffect() else {
                return false
            }
            orderTransaction.schedulePersistence()
            return true
        }

        return groupMutations.replaceAllAtomically(
            expected: currentGroups,
            with: planned.groups,
            applying: { [orderTransaction] in
                orderTransaction.apply(planned.plan) && sideEffect()
            }
        )
    }
}
