import Foundation

/// Owns profile-to-structure consistency: assigning profiles to spaces, tabs,
/// and shortcut pins, reconciling references after profile deletion, and
/// re-resolving the visible selection after a profile switch.
@MainActor
final class TabProfileAssignmentOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func cleanupProfileReferences(_ deletedProfileId: UUID, fallbackProfileId: UUID) {
        var didChange = false
        var dirtySpaceIds = Set<UUID>()
        let spacesById = Dictionary(uniqueKeysWithValues: tabManager.spaces.map { ($0.id, $0) })

        let tabsToUnload = tabManager.regularTabCollectionStateOwner.allTabs()
            .filter { tab in
                if tab.profileId == deletedProfileId { return true }
                guard let spaceId = tab.spaceId else { return false }
                return spacesById[spaceId]?.profileId == deletedProfileId
            }
        for tab in tabsToUnload {
            tab.unloadWebView()
        }

        for space in tabManager.spaces where space.profileId == deletedProfileId {
            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.assignProfile(
                spaceId: space.id,
                profileId: fallbackProfileId
            )
            didChange = true
        }

        for (spaceId, tabs) in tabManager.regularTabCollectionStateOwner.tabsBySpace {
            let resolvedProfileId = tabManager.spaceCollectionStateOwner.profileId(for: spaceId)
                ?? fallbackProfileId
            for tab in tabs where tab.profileId == deletedProfileId {
                tab.profileId = resolvedProfileId
                dirtySpaceIds.insert(spaceId)
                didChange = true
            }
        }

        if let removedPins = tabManager.pinnedByProfile.removeValue(forKey: deletedProfileId),
           !removedPins.isEmpty {
            tabManager.structuralPersistence.recordShortcutPinsStructuralChange(previous: removedPins, current: [])
            tabManager.structuralPersistence.markPinnedSnapshotDirty(for: deletedProfileId)
            didChange = true
        }

        let pinnedProfilesWithDeletedExecution = tabManager.pinnedByProfile.compactMap { profileId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (profileId, pins) : nil
        }
        for (profileId, pins) in pinnedProfilesWithDeletedExecution {
            tabManager.setPinnedTabs(
                tabManager.shortcutPinStoreOwner.reindexed(
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

        let spacesWithDeletedExecution = tabManager.spacePinnedShortcuts.compactMap { spaceId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (spaceId, pins) : nil
        }
        for (spaceId, pins) in spacesWithDeletedExecution {
            tabManager.setSpacePinnedShortcuts(
                tabManager.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(
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
            tabManager.markAllSpacesStructurallyDirty()
            for spaceId in dirtySpaceIds {
                tabManager.structuralPersistence.markRegularTabsStructurallyDirty(for: spaceId)
            }
            tabManager.scheduleStructuralPersistence()
        }
        handleProfileSwitch(contextWindowId: nil)
    }

    func handleProfileSwitch(contextWindowId: UUID?) {
        if let pendingSpaceId = tabManager.pendingSpaceActivation {
            tabManager.pendingSpaceActivation = nil
            if let target = tabManager.spaceCollectionStateOwner.space(with: pendingSpaceId) {
                tabManager.setActiveSpace(target, contextWindowId: contextWindowId)
            }
        }

        let visible = tabManager.selectionTabsForCurrentContext(in: contextWindowId)
        if contextWindowId == nil,
           shouldPreserveContextlessShortcutLiveTab(tabManager.currentTab) {
            tabManager.runtimeContext?.updateTabVisibility()
            return
        }

        if tabManager.currentTab == nil
            || !(visible.contains { $0.id == tabManager.currentTab!.id }) {
            tabManager.currentTab = visible.first
            tabManager.runtimeContext?.updateTabVisibility()
            tabManager.structuralPersistence.persistSelection()
        } else {
            tabManager.runtimeContext?.updateTabVisibility()
        }
    }

    private func shouldPreserveContextlessShortcutLiveTab(_ tab: Tab?) -> Bool {
        guard let tab,
              tab.isShortcutLiveInstance,
              tab.shortcutPinRole != .essential,
              let shortcutPinId = tab.shortcutPinId,
              tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutPinId) != nil
        else {
            return false
        }
        return true
    }

    func reconcileSpaceProfilesIfNeeded() {
        let defaultProfileId = tabManager.runtimeContext?.defaultProfileId
        guard let profileId = defaultProfileId else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "TabManager"
            )
            return
        }

        var didAssign = false
        for space in tabManager.spaces where space.profileId == nil {
            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.assignProfile(spaceId: space.id, profileId: profileId)
            didAssign = true
        }

        if didAssign {
            tabManager.markAllSpacesStructurallyDirty()
            tabManager.scheduleStructuralPersistence()
        }
    }

    func assign(spaceId: UUID, toProfile profileId: UUID) {
        if tabManager.spaceCollectionStateOwner.space(with: spaceId) != nil {
            let exists = tabManager.runtimeContext?.profileExists(profileId) ?? false
            if !exists {
                RuntimeDiagnostics.emit(
                    "⚠️ [TabManager] Attempted to assign space to unknown profile: \(profileId)"
                )
                return
            }
            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.assignProfile(spaceId: spaceId, profileId: profileId)
            tabManager.markAllSpacesStructurallyDirty()
            tabManager.scheduleStructuralPersistence()
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
            tabManager.structuralPersistence.markRegularTabsStructurallyDirty(for: spaceId)
        }
        tabManager.scheduleStructuralPersistence()
        tabManager.requestStructuralPublish()
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

        let currentPin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) ?? pin
        guard currentPin.executionProfileId != profileId else { return currentPin }
        return tabManager.shortcutPinCommandOwner.updateShortcutPin(
            currentPin,
            executionProfileId: .some(profileId)
        )
    }

    func assignProfile(_ profileId: UUID?, to tab: Tab) {
        guard tab.profileId != profileId else { return }

        let targetURL = tab.existingWebView?.url ?? tab.url
        let trackedWindowIds = tabManager.runtimeContext?.webViewLifecycle
            .windowIDsTrackingWebViews(for: tab.id) ?? []
        let hasTrackedWebViews = trackedWindowIds.isEmpty == false || tab.primaryWindowId != nil
        let hasUntrackedWebView = tab.existingWebView != nil && !hasTrackedWebViews

        if hasTrackedWebViews,
           #available(macOS 15.5, *) {
            tab.profileId = profileId
            tabManager.runtimeContext?.webViewLifecycle.rebuildLiveWebViews(
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
        tabManager.runtimeContext?.profileExists(profileId) ?? true
    }
}
