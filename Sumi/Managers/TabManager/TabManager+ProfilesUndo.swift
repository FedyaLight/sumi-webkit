import Foundation

// MARK: - Profile Cleanup & Stats
extension TabManager {
    func cleanupProfileReferences(_ deletedProfileId: UUID, fallbackProfileId: UUID) {
        var didChange = false
        var dirtySpaceIds = Set<UUID>()
        let spacesById = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })

        let tabsToUnload = tabsBySpace.values
            .flatMap(\.self)
            .filter { tab in
                if tab.profileId == deletedProfileId { return true }
                guard let spaceId = tab.spaceId else { return false }
                return spacesById[spaceId]?.profileId == deletedProfileId
            }
        for tab in tabsToUnload {
            tab.unloadWebView()
        }

        for index in spaces.indices where spaces[index].profileId == deletedProfileId {
            spaces[index].profileId = fallbackProfileId
            if currentSpace?.id == spaces[index].id {
                currentSpace?.profileId = fallbackProfileId
            }
            didChange = true
        }

        for (spaceId, tabs) in tabsBySpace {
            let resolvedProfileId = spaces.first(where: { $0.id == spaceId })?.profileId ?? fallbackProfileId
            for tab in tabs where tab.profileId == deletedProfileId {
                tab.profileId = resolvedProfileId
                dirtySpaceIds.insert(spaceId)
                didChange = true
            }
        }

        if let removedPins = pinnedByProfile.removeValue(forKey: deletedProfileId),
           !removedPins.isEmpty {
            recordShortcutPinsStructuralChange(previous: removedPins, current: [])
            markPinnedSnapshotDirty(for: deletedProfileId)
            didChange = true
        }

        let pinnedProfilesWithDeletedExecution = pinnedByProfile.compactMap { profileId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (profileId, pins) : nil
        }
        for (profileId, pins) in pinnedProfilesWithDeletedExecution {
            setPinnedTabs(
                reindexed(
                    pins.map { pin in
                        pin.executionProfileId == deletedProfileId
                            ? pin.updated(executionProfileId: .some(nil))
                            : pin
                    }
                ),
                for: profileId
            )
            didChange = true
        }

        let spacesWithDeletedExecution = spacePinnedShortcuts.compactMap { spaceId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (spaceId, pins) : nil
        }
        for (spaceId, pins) in spacesWithDeletedExecution {
            setSpacePinnedShortcuts(
                normalizedSpacePinnedShortcuts(
                    pins.map { pin in
                        pin.executionProfileId == deletedProfileId
                            ? pin.updated(executionProfileId: .some(nil))
                            : pin
                    }
                ),
                for: spaceId
            )
            didChange = true
        }

        if didChange {
            markAllSpacesStructurallyDirty()
            for spaceId in dirtySpaceIds {
                markRegularTabsStructurallyDirty(for: spaceId)
            }
            scheduleStructuralPersistence()
        }
        handleProfileSwitch()
    }

    func tabs(in space: Space) -> [Tab] {
        regularTabCollectionOwner.tabs(in: space)
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
            runtimeContext?.updateTabVisibility()
            persistSelection()
        } else {
            runtimeContext?.updateTabVisibility()
        }
    }
}

// MARK: - Profile Assignment Helpers
extension TabManager {
    func reconcileSpaceProfilesIfNeeded() {
        let defaultProfileId = runtimeContext?.defaultProfileId
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
            let exists = runtimeContext?.profileExists(profileId) ?? false
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

    @discardableResult
    func assign(tab: Tab, toProfile profileId: UUID) -> Bool {
        guard profileExists(profileId) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign tab to unknown profile: \(profileId)"
            )
            return false
        }

        guard tab.profileId != profileId else { return false }
        assignProfile(profileId, to: tab)
        if let spaceId = tab.spaceId {
            markRegularTabsStructurallyDirty(for: spaceId)
        }
        scheduleStructuralPersistence()
        requestStructuralPublish()
        return true
    }

    @discardableResult
    func assign(shortcutPin pin: ShortcutPin, toExecutionProfile profileId: UUID) -> ShortcutPin? {
        guard profileExists(profileId) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign pinned tab to unknown profile: \(profileId)"
            )
            return nil
        }

        let currentPin = shortcutPin(by: pin.id) ?? pin
        guard currentPin.executionProfileId != profileId else { return currentPin }
        return updateShortcutPin(
            currentPin,
            executionProfileId: .some(profileId)
        )
    }

    func assignProfile(_ profileId: UUID?, to tab: Tab) {
        guard tab.profileId != profileId else { return }

        let targetURL = tab.existingWebView?.url ?? tab.url
        let trackedWindowIds = runtimeContext?.windowIDsTrackingWebViews(for: tab.id) ?? []
        let hasTrackedWebViews = trackedWindowIds.isEmpty == false || tab.primaryWindowId != nil
        let hasUntrackedWebView = tab.existingWebView != nil && !hasTrackedWebViews

        if hasTrackedWebViews,
           #available(macOS 15.5, *) {
            tab.profileId = profileId
            runtimeContext?.rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: tab.primaryWindowId,
                load: targetURL
            )
        } else if hasTrackedWebViews || hasUntrackedWebView {
            tab.unloadWebView()
            tab.profileId = profileId
            tab.loadWebViewIfNeeded()
        } else {
            tab.profileId = profileId
        }
    }

    func profileExists(_ profileId: UUID) -> Bool {
        runtimeContext?.profileExists(profileId) ?? true
    }
}

// MARK: - Tab Closure Undo
extension TabManager {
    func captureRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        runtimeContext?.captureClosedTab(tab, sourceSpaceId: spaceId)
        runtimeContext?.presentTabClosureToast(tabCount: 1)
    }

    private func captureRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        for (tab, spaceId) in tabs {
            runtimeContext?.captureClosedTab(tab, sourceSpaceId: spaceId)
        }

        runtimeContext?.presentTabClosureToast(tabCount: count)
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
            guard let tabsBelow = regularTabCollectionOwner.tabsBelow(tab) else { return }
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

        if let removal = regularTabCollectionOwner.remove(
            id,
            in: spaces,
            currentSpaceId: currentSpace?.id
        ) {
            removed = removal.tab
            removedIndexInCurrentSpace = removal.indexInCurrentSpace
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

        runtimeContext?.unloadTab(tab)
        runtimeContext?.requireRemoveAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )

        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )

        if wasCurrent {
            if tab.spaceId == nil {
                let tabs = essentialTabs(for: runtimeContext?.currentProfileId)
                if let first = tabs.first {
                    setActiveTab(first)
                }
            } else if let spaceId = tab.spaceId {
                let spaceTabs = regularTabCollectionOwner.tabs(in: spaceId)
                if !spaceTabs.isEmpty {
                    let targetIndex = min(removedIndexInCurrentSpace ?? 0, spaceTabs.count - 1)
                    setActiveTab(spaceTabs[targetIndex])
                }
            }
        }

        scheduleStructuralPersistence()
    }
}
