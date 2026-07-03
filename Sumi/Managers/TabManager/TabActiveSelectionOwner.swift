import Foundation

@MainActor
final class TabActiveSelectionOwner {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func setActiveTab(_ tab: Tab) {
        guard tabManager.contains(tab) else {
            return
        }
        let previous = tabManager.currentTab
        if previous?.id != tab.id {
            tabManager.currentTab = tab
        }

        updateActiveSplitSelection(for: tab)
        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: false)

        if previous?.id != tab.id {
            tabManager.runtimeContext?.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: previous
            )
        }

        tabManager.structuralPersistence.persistSelection()
    }

    /// Update only the global tab state without triggering UI operations.
    /// Used when BrowserManager.selectTab() has already handled all UI concerns.
    func updateActiveTabState(_ tab: Tab) {
        guard tabManager.contains(tab) else {
            return
        }
        tabManager.currentTab = tab
        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: true)

        tabManager.structuralPersistence.persistSelection()
    }

    private func updateActiveSplitSelection(for tab: Tab) {
        guard let runtimeContext = tabManager.runtimeContext else { return }
        runtimeContext.forEachWindow { windowId, windowState in
            if runtimeContext.visibleSplitTabIds(for: windowId).contains(tab.id) {
                runtimeContext.updateActiveSplitSide(for: tab.id, in: windowId)
                if windowState.currentTabId != tab.id {
                    windowState.currentTabId = tab.id
                }
            }
        }
    }

    private func updateActiveTabSpaceSelectionState(
        for tab: Tab,
        refreshCurrentSpaceReference: Bool
    ) {
        var didChangeSpacePersistenceState = false
        if let spaceId = tab.spaceId,
           let space = tabManager.spaces.first(where: { $0.id == spaceId }) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
            if refreshCurrentSpaceReference || tabManager.currentSpace?.id != space.id {
                tabManager.currentSpace = space
            }
        } else if let currentSpace = tabManager.currentSpace {
            if currentSpace.activeTabId != tab.id {
                currentSpace.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
        }
        if didChangeSpacePersistenceState {
            tabManager.structuralPersistence.markSpacesSnapshotDirty()
        }
    }
}
