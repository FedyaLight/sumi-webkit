import Foundation

@MainActor
final class TabProfileRuntimeStateOwner {
    struct Dependencies {
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let regularTabCollectionStateOwner: RegularTabCollectionStateOwner
        let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
        let folderCollectionStateOwner: TabFolderCollectionStateOwner
        let transientShortcutTabs: @MainActor () -> [Tab]
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func hasLiveRuntimeContent(in space: Space) -> Bool {
        let spaceId = space.id

        if dependencies.regularTabCollectionStateOwner.hasTabs(in: spaceId) { return true }
        if dependencies.shortcutPinCollectionStateOwner.hasSpacePinnedShortcuts(in: spaceId) { return true }
        if dependencies.folderCollectionStateOwner.hasFolders(in: spaceId) { return true }

        return dependencies.transientShortcutTabs()
            .contains { $0.spaceId == spaceId }
    }

    func reconcile(activeSpaceId: UUID?) {
        for space in dependencies.spaceStateOwner.spaces {
            let hasRuntimeContent = hasLiveRuntimeContent(in: space)

            if space.id == activeSpaceId {
                space.profileRuntimeState = hasRuntimeContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasRuntimeContent ? .loadedInactive : .dormant
            }
        }
    }
}

extension TabProfileRuntimeStateOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            spaceStateOwner: tabManager.spaceStateOwner,
            regularTabCollectionStateOwner: tabManager.regularTabCollectionStateOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            folderCollectionStateOwner: tabManager.folderCollectionStateOwner,
            transientShortcutTabs: { [weak tabManager] in
                tabManager?.transientTabRegistryOwner.transientShortcutTabs ?? []
            }
        )
    }
}
