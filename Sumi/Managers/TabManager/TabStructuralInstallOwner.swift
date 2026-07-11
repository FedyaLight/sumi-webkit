import Combine
import Foundation

@MainActor
final class TabStructuralInstallOwner {
    struct Dependencies {
        let withStructuralUpdateTransaction: @MainActor (@MainActor () -> Void) -> Void
        let objectWillChange: @MainActor () -> Void
        let replaceSpaces: @MainActor ([Space]) -> Void
        let replaceTabsBySpace: @MainActor ([UUID: [Tab]]) -> Void
        let replaceFoldersBySpace: @MainActor ([UUID: [TabFolder]]) -> Void
        let replaceSplitGroups: @MainActor ([SplitGroup]) -> Void
        let replaceShortcutPins: @MainActor (
            _ pinnedByProfile: [UUID: [ShortcutPin]],
            _ spacePinnedShortcuts: [UUID: [ShortcutPin]],
            _ pendingPinnedWithoutProfile: [ShortcutPin]
        ) -> Void
        let replaceCurrentSpace: @MainActor (Space?) -> Void
        let replaceCurrentTab: @MainActor (Tab?) -> Void
        let syncShortcutPins: @MainActor ([ShortcutPin]) -> Void
        let rebuildTabLookup: @MainActor () -> Void
        let markSnapshotCacheDirty: @MainActor () -> Void
        let resetStructuralDirtySet: @MainActor () -> Void
        let requestStructuralPublish: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func installRestoredCollections(
        _ restoredState: TabRestoreRuntimeState,
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?
    ) {
        install(
            spaces: restoredState.spaces,
            tabsBySpace: restoredState.tabsBySpace,
            foldersBySpace: restoredState.foldersBySpace,
            pinnedByProfile: restoredState.pinnedByProfile,
            spacePinnedShortcuts: restoredState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: restoredState.pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab,
            resetDirtyState: false
        )
    }

    func install(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        foldersBySpace: [UUID: [TabFolder]],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin],
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        resetDirtyState: Bool = true
    ) {
        dependencies.withStructuralUpdateTransaction {
            dependencies.objectWillChange()
            dependencies.replaceSpaces(spaces)
            dependencies.replaceTabsBySpace(tabsBySpace)
            dependencies.replaceFoldersBySpace(foldersBySpace)
            dependencies.replaceSplitGroups(splitGroups)
            dependencies.replaceShortcutPins(
                pinnedByProfile,
                spacePinnedShortcuts,
                pendingPinnedWithoutProfile
            )
            dependencies.replaceCurrentSpace(currentSpace)
            dependencies.replaceCurrentTab(currentTab)
            dependencies.syncShortcutPins(
                Array(pinnedByProfile.values.joined()) + Array(spacePinnedShortcuts.values.joined())
            )
            dependencies.rebuildTabLookup()
            dependencies.markSnapshotCacheDirty()
            if resetDirtyState {
                dependencies.resetStructuralDirtySet()
            }
            dependencies.requestStructuralPublish()
        }
    }
}

extension TabStructuralInstallOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            objectWillChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            replaceSpaces: { [weak tabManager] spaces in
                tabManager?.spaceStateOwner.replaceSpaces(spaces)
            },
            replaceTabsBySpace: { [weak tabManager] tabsBySpace in
                tabManager?.regularTabCollectionStateOwner.replaceTabsBySpace(tabsBySpace)
            },
            replaceFoldersBySpace: { [weak tabManager] foldersBySpace in
                tabManager?.folderCollectionStateOwner.replaceFoldersBySpace(foldersBySpace)
            },
            replaceSplitGroups: { [weak tabManager] splitGroups in
                tabManager?.splitGroupCollectionStateOwner.replaceSplitGroups(splitGroups)
            },
            replaceShortcutPins: { [weak tabManager] pinnedByProfile, spacePinnedShortcuts, pendingPinnedWithoutProfile in
                tabManager?.shortcutPinCollectionStateOwner.replaceAll(
                    pinnedByProfile: pinnedByProfile,
                    spacePinnedShortcuts: spacePinnedShortcuts,
                    pendingPinnedWithoutProfile: pendingPinnedWithoutProfile
                )
            },
            replaceCurrentSpace: { [weak tabManager] space in
                tabManager?.spaceStateOwner.replaceCurrentSpace(space)
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            syncShortcutPins: { [weak tabManager] shortcutPins in
                tabManager?.faviconService.syncShortcutPins(shortcutPins)
            },
            rebuildTabLookup: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.rebuild()
            },
            markSnapshotCacheDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markSnapshotCacheDirty()
            },
            resetStructuralDirtySet: { [weak tabManager] in
                tabManager?.structuralPersistence.resetDirtySet()
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.requestPublish()
            }
        )
    }
}
