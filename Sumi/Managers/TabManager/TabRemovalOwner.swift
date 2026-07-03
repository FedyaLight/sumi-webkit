import Foundation

@MainActor
final class TabRemovalOwner {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func removeTab(_ id: UUID) {
        tabManager.withStructuralUpdateTransaction {
            tabManager.runtimeContext?.handleTabClosure(id)
            tabManager.structuralPersistence.cancelRuntimeStatePersistence(for: id)

            let wasCurrent = (tabManager.currentTab?.id == id)
            var removed: Tab?
            var removedSpaceId: UUID?
            var removedIndexInCurrentSpace: Int?

            if tabManager.removeTransientExtensionTab(id: id) {
                return
            }

            if tabManager.transientWebKitTabLifecycleOwner.closeAuxiliaryMiniWindowTabIfPresent(id: id) {
                return
            }

            if let removal = tabManager.regularTabCollectionOwner.remove(
                id,
                in: tabManager.spaces,
                currentSpaceId: tabManager.currentSpace?.id
            ) {
                removed = removal.tab
                removedSpaceId = removal.spaceId
                removedIndexInCurrentSpace = removal.indexInCurrentSpace
            }
            if removed == nil,
               let removal = tabManager.transientTabRegistryOwner
                   .removeTransientShortcutTab(tabId: id) {
                _ = removal.windowId
                _ = removal.pinId
                tabManager.notifyTransientShortcutStateChanged()
                removed = removal.tab
            }

            guard let tab = removed else { return }
            let runtimeContext = tabManager.requireRuntimeContext()

            runtimeContext.notifyTabClosedIfLoaded(tab)

            runtimeContext.forEachWindowState { windowState in
                windowState.removeFromRegularTabHistory(tab.id)
            }

            captureRecentlyClosedTab(tab, spaceId: removedSpaceId)

            runtimeContext.webViewLifecycle.unloadTab(tab)
            runtimeContext.webViewLifecycle.requireRemoveAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
            tabManager.detach(tab)

            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )

            if wasCurrent {
                updateCurrentTabAfterRemovingCurrentTab(
                    tab,
                    removedIndexInCurrentSpace: removedIndexInCurrentSpace
                )
            }

            tabManager.scheduleStructuralPersistence()
            runtimeContext.validateWindowStates()
        }
    }

    private func updateCurrentTabAfterRemovingCurrentTab(
        _ tab: Tab,
        removedIndexInCurrentSpace: Int?
    ) {
        if tab.spaceId == nil {
            updateCurrentTabAfterRemovingGlobalPinnedTab()
        } else if let currentSpace = tabManager.currentSpace {
            updateCurrentTabAfterRemovingSpaceTab(
                in: currentSpace,
                removedIndexInCurrentSpace: removedIndexInCurrentSpace
            )
        }
    }

    private func updateCurrentTabAfterRemovingGlobalPinnedTab() {
        if !tabManager.pinnedTabs.isEmpty {
            tabManager.currentTab = tabManager.pinnedTabs.last
        } else if let currentSpace = tabManager.currentSpace {
            let spacePinnedTabs = tabManager.liveSpacePinnedTabs(for: currentSpace.id)
            let regularTabs = tabManager.regularTabCollectionOwner.tabs(in: currentSpace.id)
            tabManager.currentTab = spacePinnedTabs.last ?? regularTabs.last
        } else {
            tabManager.currentTab = nil
        }
    }

    private func updateCurrentTabAfterRemovingSpaceTab(
        in currentSpace: Space,
        removedIndexInCurrentSpace: Int?
    ) {
        let spacePinnedTabs = tabManager.liveSpacePinnedTabs(for: currentSpace.id)
        let regularTabs = tabManager.regularTabCollectionOwner.tabs(in: currentSpace.id)

        if let removedIndexInCurrentSpace {
            let allSpaceTabs = spacePinnedTabs + regularTabs
            if !allSpaceTabs.isEmpty {
                let newIndex = min(removedIndexInCurrentSpace, allSpaceTabs.count - 1)
                tabManager.currentTab = allSpaceTabs.indices.contains(newIndex)
                    ? allSpaceTabs[newIndex]
                    : allSpaceTabs.first
            } else if !tabManager.pinnedTabs.isEmpty {
                tabManager.currentTab = tabManager.pinnedTabs.last
            } else {
                tabManager.currentTab = nil
            }
        } else {
            tabManager.currentTab = regularTabs.last
                ?? spacePinnedTabs.last
                ?? tabManager.pinnedTabs.last
        }
    }

    // MARK: - Closure Undo Capture

    func captureRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        tabManager.runtimeContext?.captureClosedTab(tab, sourceSpaceId: spaceId)
        tabManager.runtimeContext?.presentTabClosureToast(tabCount: 1)
    }

    private func captureRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        for (tab, spaceId) in tabs {
            tabManager.runtimeContext?.captureClosedTab(tab, sourceSpaceId: spaceId)
        }

        tabManager.runtimeContext?.presentTabClosureToast(tabCount: count)
    }

    // MARK: - Bulk Removal

    func closeAllTabsBelow(_ tab: Tab) {
        tabManager.withStructuralUpdateTransaction {
            guard let spaceId = tab.spaceId else { return }
            guard let tabsBelow = tabManager.regularTabCollectionOwner.tabsBelow(tab) else { return }
            if tabsBelow.isEmpty {
                return
            }

            let tabsToTrack = tabsBelow.map { (tab: $0, spaceId: spaceId) }
            for tabToClose in tabsBelow {
                closeTabWithoutTracking(tabToClose.id)
            }

            captureRecentlyClosedTabs(tabsToTrack, count: tabsBelow.count)
        }
    }

    private func closeTabWithoutTracking(_ id: UUID) {
        tabManager.structuralPersistence.cancelRuntimeStatePersistence(for: id)
        let wasCurrent = tabManager.currentTab?.id == id
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        if let removal = tabManager.regularTabCollectionOwner.remove(
            id,
            in: tabManager.spaces,
            currentSpaceId: tabManager.currentSpace?.id
        ) {
            removed = removal.tab
            removedIndexInCurrentSpace = removal.indexInCurrentSpace
        }

        if removed == nil,
           let removal = tabManager.transientTabRegistryOwner.removeTransientShortcutTab(tabId: id) {
            _ = removal.windowId
            _ = removal.pinId
            tabManager.notifyTransientShortcutStateChanged()
            removed = removal.tab
        }

        guard let tab = removed else { return }

        let runtimeContext = tabManager.requireRuntimeContext()
        runtimeContext.webViewLifecycle.unloadTab(tab)
        runtimeContext.webViewLifecycle.requireRemoveAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )

        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )

        if wasCurrent {
            if tab.spaceId == nil {
                let tabs = tabManager.shortcutPresentationOwner.activeEssentialTabs(for: runtimeContext.currentProfileId)
                if let first = tabs.first {
                    tabManager.setActiveTab(first)
                }
            } else if let spaceId = tab.spaceId {
                let spaceTabs = tabManager.regularTabCollectionOwner.tabs(in: spaceId)
                if !spaceTabs.isEmpty {
                    let targetIndex = min(removedIndexInCurrentSpace ?? 0, spaceTabs.count - 1)
                    tabManager.setActiveTab(spaceTabs[targetIndex])
                }
            }
        }

        tabManager.scheduleStructuralPersistence()
    }
}
