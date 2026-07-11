import Foundation
import SumiDomain

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
            regularTabIDs: restoredRegularTabIDs(restoredTabs),
            shortcutReturnPlacementsByPinID:
                restoredShortcutReturnPlacements(restoredTabs),
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

    private func restoredRegularTabIDs(
        _ tabs: TabRestoreCategorizedTabs
    ) -> Set<UUID> {
        Set(
            tabs.regularTabsBySpace.values.flatMap { $0.map(\.id) }
        )
    }

    private func restoredShortcutReturnPlacements(
        _ tabs: TabRestoreCategorizedTabs
    ) -> [UUID: SumiDomain.SplitShortcutReturnPlacement] {
        let shortcuts =
            tabs.pinnedShortcutsByProfile.values.flatMap { $0 }
                + tabs.pendingPinnedShortcuts
                + tabs.spacePinnedShortcutsBySpace.values.flatMap { $0 }
        return shortcuts.reduce(into: [:]) { placements, shortcut in
            guard placements[shortcut.id] == nil else { return }
            switch shortcut.role {
            case .essential:
                placements[shortcut.id] = .essential(
                    profileId: shortcut.profileId,
                    index: shortcut.index
                )
            case .spacePinned:
                guard let spaceID = shortcut.spaceId else { return }
                placements[shortcut.id] = .spacePinned(
                    spaceId: spaceID,
                    folderId: shortcut.folderId,
                    index: shortcut.index
                )
            }
        }
    }
}
