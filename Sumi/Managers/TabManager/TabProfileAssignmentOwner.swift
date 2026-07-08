import Foundation

/// Owns profile-to-structure consistency: assigning profiles to spaces, tabs,
/// and shortcut pins, reconciling references after profile deletion, and
/// re-resolving the visible selection after a profile switch.
@MainActor
final class TabProfileAssignmentOwner {
    struct Dependencies {
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let regularTabCollectionStateOwner: RegularTabCollectionStateOwner
        let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
        let sendObjectWillChange: () -> Void
        let recordShortcutPinsStructuralChange: ([ShortcutPin], [ShortcutPin]) -> Void
        let markPinnedSnapshotDirty: (UUID) -> Void
        let setPinnedTabs: ([ShortcutPin], UUID) -> Void
        let reindexedPins: ([ShortcutPin]) -> [ShortcutPin]
        let setSpacePinnedShortcuts: ([ShortcutPin], UUID) -> Void
        let normalizedSpacePinnedShortcuts: ([ShortcutPin]) -> [ShortcutPin]
        let markAllSpacesStructurallyDirty: () -> Void
        let markRegularTabsStructurallyDirty: (UUID) -> Void
        let scheduleStructuralPersistence: () -> Void
        let pendingSpaceActivation: () -> UUID?
        let setPendingSpaceActivation: (UUID?) -> Void
        let setActiveSpace: (Space, UUID?) -> Void
        let selectionTabsForCurrentContext: (UUID?) -> [Tab]
        let currentTab: () -> Tab?
        let replaceCurrentTab: (Tab?) -> Void
        let updateTabVisibility: () -> Void
        let persistSelection: () -> Void
        let defaultProfileId: () -> UUID?
        let profileExists: (UUID) -> Bool
        let requestStructuralPublish: () -> Void
        let updateShortcutPinExecutionProfile: (ShortcutPin, UUID) -> ShortcutPin?
        let windowIDsTrackingWebViews: (UUID) -> [UUID]
        let primaryTrackedWindowId: (UUID) -> UUID?
        let rebuildLiveWebViews: (Tab, UUID?, URL) -> Void
        let liveDocumentURL: (Tab) -> URL?
        let hasUntrackedOwnedWebView: (Tab) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func cleanupProfileReferences(_ deletedProfileId: UUID, fallbackProfileId: UUID) {
        var didChange = false
        var dirtySpaceIds = Set<UUID>()
        let spacesById = Dictionary(uniqueKeysWithValues: dependencies.spaceStateOwner.spaces.map { ($0.id, $0) })

        let tabsToUnload = dependencies.regularTabCollectionStateOwner.allTabs()
            .filter { tab in
                if tab.profileId == deletedProfileId { return true }
                guard let spaceId = tab.spaceId else { return false }
                return spacesById[spaceId]?.profileId == deletedProfileId
            }
        for tab in tabsToUnload {
            tab.unloadWebView()
        }

        for space in dependencies.spaceStateOwner.spaces where space.profileId == deletedProfileId {
            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.assignProfile(
                spaceId: space.id,
                profileId: fallbackProfileId
            )
            didChange = true
        }

        for (spaceId, tabs) in dependencies.regularTabCollectionStateOwner.tabsBySpace {
            let resolvedProfileId = dependencies.spaceStateOwner.profileId(for: spaceId)
                ?? fallbackProfileId
            for tab in tabs where tab.profileId == deletedProfileId {
                tab.profileId = resolvedProfileId
                dirtySpaceIds.insert(spaceId)
                didChange = true
            }
        }

        let removedPins = dependencies.shortcutPinCollectionStateOwner
            .pinnedByProfileSnapshot()[deletedProfileId] ?? []
        if !removedPins.isEmpty {
            dependencies.sendObjectWillChange()
            dependencies.shortcutPinCollectionStateOwner.removePinnedPins(for: deletedProfileId)
            dependencies.recordShortcutPinsStructuralChange(removedPins, [])
            dependencies.markPinnedSnapshotDirty(deletedProfileId)
            didChange = true
        }

        let pinnedProfilesWithDeletedExecution = dependencies.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot().compactMap { profileId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (profileId, pins) : nil
        }
        for (profileId, pins) in pinnedProfilesWithDeletedExecution {
            dependencies.setPinnedTabs(
                dependencies.reindexedPins(
                    pins.map { pin in
                        pin.executionProfileId == deletedProfileId
                            ? pin.updated(executionProfileId: .some(nil))
                            : pin
                    }
                ),
                profileId
            )
            didChange = true
        }

        let spacesWithDeletedExecution = dependencies.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot().compactMap { spaceId, pins in
            pins.contains(where: { $0.executionProfileId == deletedProfileId }) ? (spaceId, pins) : nil
        }
        for (spaceId, pins) in spacesWithDeletedExecution {
            dependencies.setSpacePinnedShortcuts(
                dependencies.normalizedSpacePinnedShortcuts(
                    pins.map { pin in
                        pin.executionProfileId == deletedProfileId
                            ? pin.updated(executionProfileId: .some(nil))
                            : pin
                    }
                ),
                spaceId
            )
            didChange = true
        }

        if didChange {
            dependencies.markAllSpacesStructurallyDirty()
            for spaceId in dirtySpaceIds {
                dependencies.markRegularTabsStructurallyDirty(spaceId)
            }
            dependencies.scheduleStructuralPersistence()
        }
        handleProfileSwitch(contextWindowId: nil)
    }

    func handleProfileSwitch(contextWindowId: UUID? = nil) {
        if let pendingSpaceId = dependencies.pendingSpaceActivation() {
            dependencies.setPendingSpaceActivation(nil)
            if let target = dependencies.spaceStateOwner.space(with: pendingSpaceId) {
                dependencies.setActiveSpace(target, contextWindowId)
            }
        }

        let visible = dependencies.selectionTabsForCurrentContext(contextWindowId)
        if contextWindowId == nil,
           shouldPreserveContextlessShortcutLiveTab(dependencies.currentTab()) {
            dependencies.updateTabVisibility()
            return
        }

        if dependencies.currentTab() == nil
            || !(visible.contains { $0.id == dependencies.currentTab()!.id }) {
            dependencies.replaceCurrentTab(visible.first)
            dependencies.updateTabVisibility()
            dependencies.persistSelection()
        } else {
            dependencies.updateTabVisibility()
        }
    }

    private func shouldPreserveContextlessShortcutLiveTab(_ tab: Tab?) -> Bool {
        guard let tab,
              tab.isShortcutLiveInstance,
              tab.shortcutPinRole != .essential,
              let shortcutPinId = tab.shortcutPinId,
              dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutPinId) != nil
        else {
            return false
        }
        return true
    }

    func reconcileSpaceProfilesIfNeeded() {
        let defaultProfileId = dependencies.defaultProfileId()
        guard let profileId = defaultProfileId else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "TabManager"
            )
            return
        }

        var didAssign = false
        for space in dependencies.spaceStateOwner.spaces where space.profileId == nil {
            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.assignProfile(spaceId: space.id, profileId: profileId)
            didAssign = true
        }

        if didAssign {
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
        }
    }

    func assign(spaceId: UUID, toProfile profileId: UUID) {
        if dependencies.spaceStateOwner.space(with: spaceId) != nil {
            let exists = dependencies.profileExists(profileId)
            if !exists {
                RuntimeDiagnostics.emit(
                    "⚠️ [TabManager] Attempted to assign space to unknown profile: \(profileId)"
                )
                return
            }
            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.assignProfile(spaceId: spaceId, profileId: profileId)
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
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
            dependencies.markRegularTabsStructurallyDirty(spaceId)
        }
        dependencies.scheduleStructuralPersistence()
        dependencies.requestStructuralPublish()
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

        let currentPin = dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) ?? pin
        guard currentPin.executionProfileId != profileId else { return currentPin }
        return dependencies.updateShortcutPinExecutionProfile(currentPin, profileId)
    }

    func assignProfile(_ profileId: UUID?, to tab: Tab) {
        guard tab.profileId != profileId else { return }

        let targetURL = dependencies.liveDocumentURL(tab) ?? tab.url
        let trackedWindowIds = dependencies.windowIDsTrackingWebViews(tab.id)
        let preferredPrimaryWindowId = dependencies.primaryTrackedWindowId(tab.id)
        let hasTrackedWebViews = trackedWindowIds.isEmpty == false || preferredPrimaryWindowId != nil
        let hasUntrackedWebView = dependencies.hasUntrackedOwnedWebView(tab) && !hasTrackedWebViews

        if hasTrackedWebViews,
           #available(macOS 15.5, *) {
            tab.profileId = profileId
            dependencies.rebuildLiveWebViews(tab, preferredPrimaryWindowId, targetURL)
        } else if hasTrackedWebViews || hasUntrackedWebView {
            tab.unloadWebView()
            tab.profileId = profileId
            tab.loadWebViewIfNeeded()
        } else {
            tab.profileId = profileId
        }
    }

    func profileExists(_ profileId: UUID) -> Bool {
        dependencies.profileExists(profileId)
    }
}

extension TabProfileAssignmentOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            spaceStateOwner: tabManager.spaceStateOwner,
            regularTabCollectionStateOwner: tabManager.regularTabCollectionStateOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            sendObjectWillChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            recordShortcutPinsStructuralChange: { [weak tabManager] previous, current in
                tabManager?.structuralPersistence.recordShortcutPinsStructuralChange(previous: previous, current: current)
            },
            markPinnedSnapshotDirty: { [weak tabManager] profileId in
                tabManager?.structuralPersistence.markPinnedSnapshotDirty(for: profileId)
            },
            setPinnedTabs: { [weak tabManager] pins, profileId in
                tabManager?.structuralCollectionMutationOwner.setPinnedTabs(pins, for: profileId)
            },
            reindexedPins: { [weak tabManager] pins in
                tabManager?.shortcutPinStoreOwner.reindexed(pins) ?? pins
            },
            setSpacePinnedShortcuts: { [weak tabManager] pins, spaceId in
                tabManager?.structuralCollectionMutationOwner.setSpacePinnedShortcuts(pins, for: spaceId)
            },
            normalizedSpacePinnedShortcuts: { [weak tabManager] pins in
                tabManager?.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(pins) ?? pins
            },
            markAllSpacesStructurallyDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markAllSpacesStructurallyDirty()
            },
            markRegularTabsStructurallyDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markRegularTabsStructurallyDirty(for: spaceId)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            pendingSpaceActivation: { [weak tabManager] in
                tabManager?.pendingSpaceActivation
            },
            setPendingSpaceActivation: { [weak tabManager] spaceId in
                tabManager?.pendingSpaceActivation = spaceId
            },
            setActiveSpace: { [weak tabManager] space, windowId in
                tabManager?.spaceLifecycleOwner.setActiveSpace(space, contextWindowId: windowId)
            },
            selectionTabsForCurrentContext: { [weak tabManager] windowId in
                tabManager?.activeSelectionOwner.selectionTabsForCurrentContext(in: windowId) ?? []
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            updateTabVisibility: { [weak tabManager] in
                tabManager?.runtimeContext?.updateTabVisibility()
            },
            persistSelection: { [weak tabManager] in
                tabManager?.structuralPersistence.persistSelection()
            },
            defaultProfileId: { [weak tabManager] in
                tabManager?.runtimeContext?.defaultProfileId
            },
            profileExists: { [weak tabManager] profileId in
                tabManager?.runtimeContext?.profileExists(profileId) ?? true
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.requestStructuralPublish()
            },
            updateShortcutPinExecutionProfile: { [weak tabManager] pin, profileId in
                tabManager?.shortcutPinCommandOwner.updateShortcutPin(
                    pin,
                    executionProfileId: .some(profileId)
                )
            },
            windowIDsTrackingWebViews: { [weak tabManager] tabId in
                tabManager?.runtimeContext?.webViewLifecycle.windowIDsTrackingWebViews(for: tabId) ?? []
            },
            primaryTrackedWindowId: { [weak tabManager] tabId in
                tabManager?.runtimeContext?.webViewLifecycle.primaryTrackedWindowId(for: tabId)
            },
            rebuildLiveWebViews: { [weak tabManager] tab, windowId, url in
                tabManager?.runtimeContext?.webViewLifecycle.rebuildLiveWebViews(
                    for: tab,
                    preferredPrimaryWindowId: windowId,
                    load: url
                )
            },
            liveDocumentURL: { [weak tabManager] tab in
                tabManager?.runtimeContext?.webViewLifecycle.anyLiveWebView(for: tab)?.url
            },
            hasUntrackedOwnedWebView: { [weak tabManager] tab in
                tabManager?.runtimeContext?.webViewLifecycle.hasUntrackedOwnedWebView(for: tab) ?? false
            }
        )
    }
}
