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
            tabManager.cancelRuntimeStatePersistence(for: id)

            let wasCurrent = (tabManager.currentTab?.id == id)
            var removed: Tab?
            var removedSpaceId: UUID?
            var removedIndexInCurrentSpace: Int?

            if tabManager.removeTransientExtensionTab(id: id) {
                return
            }

            if tabManager.closeAuxiliaryMiniWindowTabIfPresent(id: id) {
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
               let (windowId, pinId, tab) = tabManager.transientShortcutTabsByWindow.lazy
                   .compactMap({ windowId, tabsByPin -> (UUID, UUID, Tab)? in
                       guard let match = tabsByPin.first(where: { $0.value.id == id }) else { return nil }
                       return (windowId, match.key, match.value)
                   })
                   .first {
                tabManager.transientShortcutTabsByWindow[windowId]?.removeValue(forKey: pinId)
                if tabManager.transientShortcutTabsByWindow[windowId]?.isEmpty == true {
                    tabManager.transientShortcutTabsByWindow.removeValue(forKey: windowId)
                }
                tabManager.notifyTransientShortcutStateChanged()
                removed = tab
            }

            guard let tab = removed else { return }
            let runtimeContext = tabManager.requireRuntimeContext()

            runtimeContext.notifyTabClosedIfLoaded(tab)

            runtimeContext.forEachWindowState { windowState in
                windowState.removeFromRegularTabHistory(tab.id)
            }

            tabManager.captureRecentlyClosedTab(tab, spaceId: removedSpaceId)

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
}
