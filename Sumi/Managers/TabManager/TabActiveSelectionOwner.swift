import Foundation

@MainActor
final class TabActiveSelectionOwner {
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let persistence: TabStructuralPersistenceService
    private let spaceSelection: TabActiveSpaceSelectionUpdater

    init(
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        persistence: TabStructuralPersistenceService,
        spaceSelection: TabActiveSpaceSelectionUpdater
    ) {
        self.membership = membership
        self.selection = selection
        self.runtimeConnection = runtimeConnection
        self.persistence = persistence
        self.spaceSelection = spaceSelection
    }

    func setActiveTab(_ tab: Tab) {
        guard membership.contains(tab) else {
            return
        }
        let previous = selection.currentTab
        if previous?.id != tab.id {
            selection.replaceCurrentTab(tab)
        }

        spaceSelection.update(
            for: tab,
            refreshCurrentSpaceReference: false
        )

        if previous?.id != tab.id {
            runtimeConnection.current?.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: previous
            )
        }

        persistence.persistSelection()
    }

    /// Update only the global tab state without triggering UI operations.
    /// Used when BrowserManager.selectTab() has already handled all UI concerns.
    func updateActiveTabState(_ tab: Tab) {
        guard membership.contains(tab) else {
            return
        }
        selection.replaceCurrentTab(tab)
        spaceSelection.update(
            for: tab,
            refreshCurrentSpaceReference: true
        )

        persistence.persistSelection()
    }
}
