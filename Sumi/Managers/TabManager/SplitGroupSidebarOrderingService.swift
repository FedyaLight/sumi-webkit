import Foundation
import SumiDomain

/// Applies sidebar placement changes for shortcut-backed split groups. Query
/// projection and mutation are kept separate from the split store itself.
@MainActor
final class SplitGroupSidebarOrderingService {
    private let store: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let orderTransaction: SpacePinnedOrderTransaction

    init(
        store: SplitGroupStore,
        mutations: SplitGroupMutationService,
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        orderTransaction: SpacePinnedOrderTransaction
    ) {
        self.store = store
        self.mutations = mutations
        self.folders = folders
        self.pins = pins
        self.orderTransaction = orderTransaction
    }

    func resolver(for spaceID: UUID) -> SplitGroupVisualOrderingResolver {
        SplitGroupVisualOrderingResolver(
            spaceID: spaceID,
            splitGroups: store.groups,
            folders: folders.folders(for: spaceID),
            spacePinnedPins: pins.spacePinnedPins(for: spaceID)
        )
    }

    func groups(for spaceID: UUID, folderID: UUID? = nil) -> [SplitGroup] {
        resolver(for: spaceID).shortcutSidebarGroups(inFolder: folderID)
    }

    func folderID(for group: SplitGroup, in spaceID: UUID) -> UUID? {
        guard group.container.spaceId == spaceID,
              group.container.isShortcutSidebar else {
            return nil
        }
        return group.container.shortcutSidebarFolderId
    }

    func topLevelItems(for spaceID: UUID) -> [SplitGroupVisualListItem] {
        resolver(for: spaceID).topLevelItems()
    }

    @discardableResult
    func moveGroup(
        _ group: SplitGroup,
        in spaceID: UUID,
        to proposedIndex: Int
    ) -> Bool {
        guard store.group(id: group.id) == group,
              case .shortcutSidebar(
                let groupSpaceID,
                _,
                nil,
                _
              ) = group.container,
              groupSpaceID == spaceID else {
            return false
        }

        let currentItems = topLevelItems(for: spaceID)
        let currentIndex = currentItems.firstIndex { item in
            if case .splitGroup(let groupID) = item { return groupID == group.id }
            return false
        }
        let targetIndex = currentIndex.map {
            SpacePinnedShortcutOrderOwner.adjustedSameContainerInsertionIndex(
                currentIndex: $0,
                proposedIndex: proposedIndex
            )
        } ?? proposedIndex
        var reorderedItems = currentItems
        let movingItem: SplitGroupVisualListItem
        if let currentIndex {
            movingItem = reorderedItems.remove(at: currentIndex)
        } else {
            movingItem = .splitGroup(group.id)
        }
        reorderedItems.insert(
            movingItem,
            at: max(0, min(targetIndex, reorderedItems.count))
        )
        guard reorderedItems != currentItems else { return false }

        return applyTopLevelOrder(reorderedItems, in: spaceID)
    }

    private func applyTopLevelOrder(
        _ items: [SplitGroupVisualListItem],
        in spaceID: UUID
    ) -> Bool {
        let currentGroups = store.groups
        guard let planned = orderTransaction.planVisualOrder(
            items,
            in: spaceID,
            groups: currentGroups
        ) else { return false }
        return mutations.replaceAll(
            expected: currentGroups,
            with: planned.groups,
            alongside: { [orderTransaction] in
                precondition(
                    orderTransaction.apply(planned.plan),
                    "Pinned order changed during synchronous split commit"
                )
            }
        )
    }
}
