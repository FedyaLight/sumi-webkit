import Foundation

@MainActor
final class TabProfileRuntimeStateOwner {
    private let spaceStateOwner: TabSpaceCollectionStateOwner
    private let regularTabCollectionStateOwner: RegularTabCollectionStateOwner
    private let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
    private let folderCollectionStateOwner: TabFolderCollectionStateOwner
    private let transientShortcutTabs: @MainActor () -> [Tab]

    init(
        spaceStateOwner: TabSpaceCollectionStateOwner,
        regularTabCollectionStateOwner: RegularTabCollectionStateOwner,
        shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner,
        folderCollectionStateOwner: TabFolderCollectionStateOwner,
        transientShortcutTabs: @escaping @MainActor () -> [Tab]
    ) {
        self.spaceStateOwner = spaceStateOwner
        self.regularTabCollectionStateOwner = regularTabCollectionStateOwner
        self.shortcutPinCollectionStateOwner = shortcutPinCollectionStateOwner
        self.folderCollectionStateOwner = folderCollectionStateOwner
        self.transientShortcutTabs = transientShortcutTabs
    }

    convenience init(tabManager: TabManager) {
        self.init(
            spaceStateOwner: tabManager.spaceStateOwner,
            regularTabCollectionStateOwner: tabManager.regularTabCollectionStateOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            folderCollectionStateOwner: tabManager.folderCollectionStateOwner,
            transientShortcutTabs: { [weak tabManager] in
                tabManager?.transientTabRegistryOwner.transientShortcutTabs ?? []
            }
        )
    }

    func hasLiveRuntimeContent(in space: Space) -> Bool {
        let spaceId = space.id

        if regularTabCollectionStateOwner.hasTabs(in: spaceId) { return true }
        if shortcutPinCollectionStateOwner.hasSpacePinnedShortcuts(in: spaceId) { return true }
        if folderCollectionStateOwner.hasFolders(in: spaceId) { return true }

        return transientShortcutTabs()
            .contains { $0.spaceId == spaceId }
    }

    func reconcile(activeSpaceId: UUID?) {
        for space in spaceStateOwner.spaces {
            let hasRuntimeContent = hasLiveRuntimeContent(in: space)

            if space.id == activeSpaceId {
                space.profileRuntimeState = hasRuntimeContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasRuntimeContent ? .loadedInactive : .dormant
            }
        }
    }
}
