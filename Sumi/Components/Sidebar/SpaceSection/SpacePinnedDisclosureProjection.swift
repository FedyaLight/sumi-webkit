import Foundation

typealias SpacePinnedListItem = SplitGroupVisualListItem

enum SpacePinnedDisclosureItem: Hashable {
    case pinned(SpacePinnedListItem)
    case nestedSticky(UUID)
}

/// Pure collapse projection kept independently testable. Rendering is owned by
/// `SpaceSidebarListView` and its single `SidebarListSurface`.
enum SpacePinnedDisclosureProjection {
    static func items(
        isCollapsed: Bool,
        pinnedItems: [SpacePinnedListItem],
        stickyItemIDs: [UUID],
        knownNestedItemIDs: Set<UUID>
    ) -> [SpacePinnedDisclosureItem] {
        guard isCollapsed else {
            return pinnedItems.map(SpacePinnedDisclosureItem.pinned)
        }

        return stickyItemIDs.compactMap { itemID in
            if let item = pinnedItems.first(where: { $0.id == itemID }) {
                return .pinned(item)
            }
            return knownNestedItemIDs.contains(itemID)
                ? .nestedSticky(itemID)
                : nil
        }
    }
}
