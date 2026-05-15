import Foundation

// MARK: - Profile Cleanup & Stats
extension TabManager {
    func cleanupProfileReferences(_ deletedProfileId: UUID) {
        guard let fallback = browserManager?.profileManager.profiles.first else { return }
        var didChange = false
        for index in spaces.indices where spaces[index].profileId == deletedProfileId {
            spaces[index].profileId = fallback.id
            if currentSpace?.id == spaces[index].id {
                currentSpace?.profileId = fallback.id
            }
            didChange = true
        }
        if didChange {
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
        handleProfileSwitch()
    }

    func tabs(in space: Space) -> [Tab] {
        Array(tabsBySpace[space.id] ?? [])
    }
}

// MARK: - Profile Change Handling
extension TabManager {
    func handleProfileSwitch() {
        if let pendingSpaceId = pendingSpaceActivation {
            pendingSpaceActivation = nil
            if let target = spaces.first(where: { $0.id == pendingSpaceId }) {
                setActiveSpace(target)
            }
        }

        let visible = selectionTabsForCurrentContext()
        if currentTab == nil || !(visible.contains { $0.id == currentTab!.id }) {
            currentTab = visible.first
            browserManager?.compositorManager.updateTabVisibility()
            persistSelection()
        } else {
            browserManager?.compositorManager.updateTabVisibility()
        }
    }
}

// MARK: - Profile Assignment Helpers
extension TabManager {
    func reconcileSpaceProfilesIfNeeded() {
        let defaultProfileId = browserManager?.currentProfile?.id
            ?? browserManager?.profileManager.profiles.first?.id
        guard let profileId = defaultProfileId else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "TabManager"
            )
            return
        }

        var didAssign = false
        for space in spaces where space.profileId == nil {
            space.profileId = profileId
            didAssign = true
        }

        if didAssign {
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }
}

// MARK: - Profile Assignment API
extension TabManager {
    func assign(spaceId: UUID, toProfile profileId: UUID) {
        if let index = spaces.firstIndex(where: { $0.id == spaceId }) {
            let exists = browserManager?.profileManager.profiles.contains(where: { $0.id == profileId }) ?? false
            if !exists {
                RuntimeDiagnostics.emit(
                    "⚠️ [TabManager] Attempted to assign space to unknown profile: \(profileId)"
                )
                return
            }
            spaces[index].profileId = profileId
            if currentSpace?.id == spaceId {
                currentSpace?.profileId = profileId
            }
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }
}

// MARK: - Tab Closure Undo
extension TabManager {
    func captureRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        let now = Date()
        let shouldShowToast = shouldShowTabClosureToast(now: now)
        lastTabClosureTime = now
        browserManager?.recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: spaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )

        if shouldShowToast {
            browserManager?.showTabClosureToast(tabCount: 1)
        }
    }

    private func captureRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        let now = Date()
        lastTabClosureTime = now

        for (tab, spaceId) in tabs {
            browserManager?.recentlyClosedManager.captureClosedTab(
                tab,
                sourceSpaceId: spaceId,
                currentURL: tab.url,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
        }

        browserManager?.showTabClosureToast(tabCount: count)
    }

    private func shouldShowTabClosureToast(now: Date) -> Bool {
        guard let lastClosure = lastTabClosureTime else { return true }
        return now.timeIntervalSince(lastClosure) >= toastCooldown
    }

    func undoCloseTab() {
        browserManager?.reopenLastClosedItem()
    }

}

// MARK: - Navigation State Management
extension TabManager {
    func updateTabNavigationState(_ tab: Tab) {
        scheduleRuntimeStatePersistence(for: tab)
    }
}

// MARK: - Bulk Tab Operations
extension TabManager {
    func closeAllTabsBelow(_ tab: Tab) {
        withStructuralUpdateTransaction {
            guard let spaceId = tab.spaceId else { return }
            guard let tabs = tabsBySpace[spaceId] else { return }
            guard tabs.firstIndex(where: { $0.id == tab.id }) != nil else { return }

            let tabsBelow = tabs.filter { $0.index > tab.index }
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
        cancelRuntimeStatePersistence(for: id)
        let wasCurrent = currentTab?.id == id
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        if removed == nil {
            for space in spaces {
                if var tabs = tabsBySpace[space.id],
                   let index = tabs.firstIndex(where: { $0.id == id })
                {
                    removed = tabs.remove(at: index)
                    removedIndexInCurrentSpace = space.id == currentSpace?.id ? index : nil
                    setTabs(tabs, for: space.id)
                    break
                }
            }
        }

        if removed == nil,
           let (windowId, pinId, tab) = transientShortcutTabsByWindow.lazy
                .compactMap({ windowId, tabsByPin -> (UUID, UUID, Tab)? in
                    guard let match = tabsByPin.first(where: { $0.value.id == id }) else { return nil }
                    return (windowId, match.key, match.value)
                })
                .first
        {
            transientShortcutTabsByWindow[windowId]?.removeValue(forKey: pinId)
            if transientShortcutTabsByWindow[windowId]?.isEmpty == true {
                transientShortcutTabsByWindow.removeValue(forKey: windowId)
            }
            notifyTransientShortcutStateChanged()
            removed = tab
        }

        guard let tab = removed else { return }

        browserManager?.compositorManager.unloadTab(tab)
        if let browserManager {
            browserManager.requireWebViewCoordinator().removeAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
        }

        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )

        if wasCurrent {
            if tab.spaceId == nil {
                let tabs = essentialTabs(for: browserManager?.currentProfile?.id)
                if let first = tabs.first {
                    setActiveTab(first)
                }
            } else if let spaceId = tab.spaceId,
                      let spaceTabs = tabsBySpace[spaceId],
                      !spaceTabs.isEmpty
            {
                let targetIndex = min(removedIndexInCurrentSpace ?? 0, spaceTabs.count - 1)
                setActiveTab(spaceTabs[targetIndex])
            }
        }

        scheduleStructuralPersistence()
    }
}
