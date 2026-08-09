import Foundation

/// Pure selection planner for the active tab after a confirmed regular-tab
/// closure. Callers must supply one coherent post-removal snapshot; this type
/// does not read live browser state.
enum SelectionAfterClosurePolicy {
    enum Decision {
        case keepCurrent
        case replaceCurrent(Tab?)
    }

    /// Post-removal ordering required to choose the next current tab.
    struct Snapshot {
        /// `true` when the closed current tab had no space binding (global pin).
        let removedWasGlobalPinned: Bool
        /// Whether a current space still exists after the removal transaction.
        let hasCurrentSpace: Bool
        let favoriteTabs: [Tab]
        let spacePinnedTabs: [Tab]
        let regularTabs: [Tab]
        /// Index of the removed tab in the pre-removal space ordering, when the
        /// removal happened in the current space.
        let removedIndexInCurrentSpace: Int?
    }

    static func decision(from snapshot: Snapshot) -> Decision {
        if snapshot.removedWasGlobalPinned {
            return .replaceCurrent(
                nextAfterRemovingGlobalPinnedTab(from: snapshot)
            )
        }
        guard snapshot.hasCurrentSpace else {
            return .keepCurrent
        }
        return .replaceCurrent(nextAfterRemovingSpaceTab(from: snapshot))
    }

    private static func nextAfterRemovingGlobalPinnedTab(
        from snapshot: Snapshot
    ) -> Tab? {
        if !snapshot.favoriteTabs.isEmpty {
            return snapshot.favoriteTabs.last
        }
        guard snapshot.hasCurrentSpace else {
            return nil
        }
        return snapshot.spacePinnedTabs.last ?? snapshot.regularTabs.last
    }

    private static func nextAfterRemovingSpaceTab(
        from snapshot: Snapshot
    ) -> Tab? {
        if let removedIndexInCurrentSpace = snapshot.removedIndexInCurrentSpace {
            let allSpaceTabs = snapshot.spacePinnedTabs + snapshot.regularTabs
            if !allSpaceTabs.isEmpty {
                let newIndex = min(
                    removedIndexInCurrentSpace,
                    allSpaceTabs.count - 1
                )
                return allSpaceTabs.indices.contains(newIndex)
                    ? allSpaceTabs[newIndex]
                    : allSpaceTabs.first
            }
            return snapshot.favoriteTabs.last
        }
        return snapshot.regularTabs.last
            ?? snapshot.spacePinnedTabs.last
            ?? snapshot.favoriteTabs.last
    }
}
