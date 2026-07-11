import Foundation

/// Derives profile runtime state from content that is actually alive in a
/// space. Persisted folders and shortcut definitions do not keep a profile
/// runtime loaded; regular tabs, materialized shortcut tabs, and the focused
/// window's selected shortcut do.
@MainActor
final class SpaceProfileRuntimeStateService {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionStateOwner
    private let liveShortcutTabs: @MainActor () -> [Tab]

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionStateOwner,
        liveShortcutTabs: @escaping @MainActor () -> [Tab]
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.liveShortcutTabs = liveShortcutTabs
    }

    func reconcile(
        focusedSpaceId: UUID?,
        selectedShortcutSpaceIds: Set<UUID> = []
    ) {
        let materializedShortcutSpaceIds: Set<UUID> = Set(
            liveShortcutTabs().compactMap { tab in
                guard tab.shortcutPinRole != .essential else { return nil }
                return tab.spaceId
            }
        )

        for space in spaces.spaces {
            let hasLiveContent = regularTabs.hasTabs(in: space.id)
                || materializedShortcutSpaceIds.contains(space.id)
                || selectedShortcutSpaceIds.contains(space.id)

            if space.id == focusedSpaceId {
                space.profileRuntimeState = hasLiveContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasLiveContent ? .loadedInactive : .dormant
            }
        }
    }
}
