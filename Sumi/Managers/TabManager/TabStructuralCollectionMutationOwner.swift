import Foundation

@MainActor
final class TabStructuralCollectionMutationOwner {
    struct Dependencies {
        let tabsBySpace: @MainActor () -> [UUID: [Tab]]
        let setTabsBySpace: @MainActor ([UUID: [Tab]]) -> Void
        let foldersBySpace: @MainActor () -> [UUID: [TabFolder]]
        let setFoldersBySpace: @MainActor ([UUID: [TabFolder]]) -> Void
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedByProfile: @MainActor ([UUID: [ShortcutPin]]) -> Void
        let spacePinnedShortcuts: @MainActor () -> [UUID: [ShortcutPin]]
        let setSpacePinnedShortcuts: @MainActor ([UUID: [ShortcutPin]]) -> Void
        let syncShortcutPins: @MainActor ([ShortcutPin]) -> Void
        let markRegularTabsSnapshotDirty: @MainActor (UUID) -> Void
        let markFoldersSnapshotDirty: @MainActor (UUID) -> Void
        let markPinnedSnapshotDirty: @MainActor (UUID) -> Void
        let markSpacePinnedSnapshotDirty: @MainActor (UUID) -> Void
        let recordRegularTabsStructuralChange: @MainActor ([Tab], [Tab]) -> Void
        let recordFoldersStructuralChange: @MainActor ([TabFolder], [TabFolder]) -> Void
        let recordShortcutPinsStructuralChange: @MainActor ([ShortcutPin], [ShortcutPin]) -> Void
        let queueTabLookupEntries: @MainActor ([Tab], [Tab]) -> Void
        let requestStructuralPublish: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func setTabs(_ items: [Tab], for spaceId: UUID) {
        var tabsBySpace = dependencies.tabsBySpace()
        let previousTabs = tabsBySpace[spaceId] ?? []
        let sortedItems = Self.sortedTabs(items)

        tabsBySpace[spaceId] = sortedItems
        dependencies.setTabsBySpace(tabsBySpace)
        dependencies.markRegularTabsSnapshotDirty(spaceId)
        dependencies.recordRegularTabsStructuralChange(previousTabs, sortedItems)
        dependencies.queueTabLookupEntries(previousTabs, sortedItems)
        dependencies.requestStructuralPublish()
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        var foldersBySpace = dependencies.foldersBySpace()
        let previousFolders = foldersBySpace[spaceId] ?? []

        foldersBySpace[spaceId] = items
        dependencies.setFoldersBySpace(foldersBySpace)
        dependencies.markFoldersSnapshotDirty(spaceId)
        dependencies.recordFoldersStructuralChange(previousFolders, items)
        dependencies.requestStructuralPublish()
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        var pinnedByProfile = dependencies.pinnedByProfile()
        let previousPins = pinnedByProfile[profileId] ?? []

        pinnedByProfile[profileId] = items
        dependencies.setPinnedByProfile(pinnedByProfile)
        syncShortcutPins(pinnedByProfile: pinnedByProfile, spacePinnedShortcuts: dependencies.spacePinnedShortcuts())
        dependencies.markPinnedSnapshotDirty(profileId)
        dependencies.recordShortcutPinsStructuralChange(previousPins, items)
        dependencies.requestStructuralPublish()
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        var spacePinnedShortcuts = dependencies.spacePinnedShortcuts()
        let previousPins = spacePinnedShortcuts[spaceId] ?? []

        spacePinnedShortcuts[spaceId] = items
        dependencies.setSpacePinnedShortcuts(spacePinnedShortcuts)
        syncShortcutPins(pinnedByProfile: dependencies.pinnedByProfile(), spacePinnedShortcuts: spacePinnedShortcuts)
        dependencies.markSpacePinnedSnapshotDirty(spaceId)
        dependencies.recordShortcutPinsStructuralChange(previousPins, items)
        dependencies.requestStructuralPublish()
    }

    private func syncShortcutPins(
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]]
    ) {
        dependencies.syncShortcutPins(
            Array(pinnedByProfile.values.joined()) + Array(spacePinnedShortcuts.values.joined())
        )
    }

    private static func sortedTabs(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

extension TabStructuralCollectionMutationOwner.Dependencies {
    static func live(tabManager: TabManager) -> Self {
        Self(
            tabsBySpace: { [weak tabManager] in
                tabManager?.tabsBySpace ?? [:]
            },
            setTabsBySpace: { [weak tabManager] tabsBySpace in
                tabManager?.tabsBySpace = tabsBySpace
            },
            foldersBySpace: { [weak tabManager] in
                tabManager?.foldersBySpace ?? [:]
            },
            setFoldersBySpace: { [weak tabManager] foldersBySpace in
                tabManager?.foldersBySpace = foldersBySpace
            },
            pinnedByProfile: { [weak tabManager] in
                tabManager?.pinnedByProfile ?? [:]
            },
            setPinnedByProfile: { [weak tabManager] pinnedByProfile in
                tabManager?.pinnedByProfile = pinnedByProfile
            },
            spacePinnedShortcuts: { [weak tabManager] in
                tabManager?.spacePinnedShortcuts ?? [:]
            },
            setSpacePinnedShortcuts: { [weak tabManager] spacePinnedShortcuts in
                tabManager?.spacePinnedShortcuts = spacePinnedShortcuts
            },
            syncShortcutPins: { [weak tabManager] shortcutPins in
                tabManager?.faviconService.syncShortcutPins(shortcutPins)
            },
            markRegularTabsSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.markRegularTabsSnapshotDirty(for: spaceId)
            },
            markFoldersSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.markFoldersSnapshotDirty(for: spaceId)
            },
            markPinnedSnapshotDirty: { [weak tabManager] profileId in
                tabManager?.markPinnedSnapshotDirty(for: profileId)
            },
            markSpacePinnedSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.markSpacePinnedSnapshotDirty(for: spaceId)
            },
            recordRegularTabsStructuralChange: { [weak tabManager] previous, current in
                tabManager?.recordRegularTabsStructuralChange(previous: previous, current: current)
            },
            recordFoldersStructuralChange: { [weak tabManager] previous, current in
                tabManager?.recordFoldersStructuralChange(previous: previous, current: current)
            },
            recordShortcutPinsStructuralChange: { [weak tabManager] previous, current in
                tabManager?.recordShortcutPinsStructuralChange(previous: previous, current: current)
            },
            queueTabLookupEntries: { [weak tabManager] previous, current in
                tabManager?.queueTabLookupEntries(removing: previous, with: current)
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.requestStructuralPublish()
            }
        )
    }
}
