import Foundation

struct TabRestorePlanner: Sendable {
    private let spaces = TabRestoreSpacePlanner()
    private let folders = TabRestoreFolderPlanner()
    private let tabs = TabRestoreTabPlanner()
    private let selection = TabRestoreSelectionPlanner()
    private let snapshotBuilder = TabRestoreSnapshotBuilder()

    func makePayload(
        from records: TabRestoreStoreRecords,
        defaultProfileId: UUID?
    ) -> TabRestorePayload {
        var repairReasons: Set<String> = []
        var restoredSpaces = spaces.makeSpaces(
            from: records.spaces,
            defaultProfileId: defaultProfileId,
            repairReasons: &repairReasons
        )
        if restoredSpaces.isEmpty {
            restoredSpaces = [spaces.makeDefaultSpace(profileId: defaultProfileId)]
            repairReasons.insert("created default space")
        }

        let validSpaceIds = Set(restoredSpaces.map(\.id))
        let restoredFolders = folders.makeFoldersBySpace(
            from: records.folders,
            validSpaceIds: validSpaceIds,
            repairReasons: &repairReasons
        )
        let validFolderIdsBySpace = restoredFolders.mapValues { Set($0.map(\.id)) }
        let restoredTabs = tabs.categorize(
            records.tabs,
            defaultProfileId: defaultProfileId,
            validSpaceIds: validSpaceIds,
            validFolderIdsBySpace: validFolderIdsBySpace,
            repairReasons: &repairReasons
        )
        let restoredSelection = selection.resolve(
            states: records.states,
            spaces: restoredSpaces,
            regularTabsBySpace: restoredTabs.regularTabsBySpace,
            repairReasons: &repairReasons
        )
        let splitGroups = TabRestoreRepair.restoreSplitGroups(
            from: records.states.first?.splitGroupsData,
            validTabIds: allRestoredTabIds(restoredTabs),
            repairReasons: &repairReasons
        )
        let snapshot = snapshotBuilder.makeSnapshot(
            spaces: restoredSpaces,
            foldersBySpace: restoredFolders,
            tabs: restoredTabs,
            splitGroups: splitGroups,
            selection: restoredSelection
        )

        return TabRestorePayload(
            spaces: restoredSpaces,
            regularTabsBySpace: restoredTabs.regularTabsBySpace,
            foldersBySpace: restoredFolders,
            pinnedShortcutsByProfile: restoredTabs.pinnedShortcutsByProfile,
            pendingPinnedShortcuts: restoredTabs.pendingPinnedShortcuts,
            spacePinnedShortcutsBySpace: restoredTabs.spacePinnedShortcutsBySpace,
            splitGroups: splitGroups,
            currentSpaceId: restoredSelection.currentSpaceID,
            currentTabId: restoredSelection.currentTabID,
            snapshot: snapshot,
            repairReasons: repairReasons.sorted(),
            totalTabCount: records.tabs.count,
            pinnedCount: restoredTabs.pinnedCount,
            spacePinnedCount: restoredTabs.spacePinnedCount,
            regularCount: restoredTabs.regularCount
        )
    }

    private func allRestoredTabIds(_ tabs: TabRestoreCategorizedTabs) -> Set<UUID> {
        Set(
            tabs.regularTabsBySpace.values.flatMap { $0.map(\.id) }
                + tabs.pinnedShortcutsByProfile.values.flatMap { $0.map(\.id) }
                + tabs.pendingPinnedShortcuts.map(\.id)
                + tabs.spacePinnedShortcutsBySpace.values.flatMap { $0.map(\.id) }
        )
    }
}
