import Foundation

@MainActor
final class TabRemovalOwner {
    struct Dependencies {
        let withStructuralUpdateTransaction: (@MainActor () -> Void) -> Void
        let requireRuntimePorts: () -> RuntimePortRegistry
        let cancelRuntimeStatePersistence: (UUID) -> Void
        let currentTab: () -> Tab?
        let replaceCurrentTab: (Tab?) -> Void
        let removeTransientExtensionTab: (UUID) -> Bool
        let closeAuxiliaryMiniWindowTabIfPresent: (UUID) -> Bool
        let removeRegularTabs: (
            Set<UUID>,
            [Space],
            UUID?
        ) -> [RegularTabCollectionOwner.Removal]
        let spaces: () -> [Space]
        let currentSpace: () -> Space?
        let retireShortcutTabIfPresent: (UUID) -> Bool
        let detach: (Tab) -> Void
        let scheduleStructuralPersistence: () -> Void
        let activeEssentialTabs: (UUID?) -> [Tab]
        let currentProfileId: () -> UUID?
        let liveSpacePinnedTabs: (UUID) -> [Tab]
        let regularTabs: (UUID) -> [Tab]
        let captureClosedTab: (Tab, UUID?) -> Void
        let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
        let tabsBelow: (Tab) -> [Tab]?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func removeTab(_ id: UUID) {
        removeTabs([id])
    }

    /// Removes a mixed candidate batch, but reports split closure only for the
    /// exact durable regular tabs that were actually present and removed.
    func removeTabs(_ ids: [UUID]) {
        dependencies.withStructuralUpdateTransaction {
            var seen = Set<UUID>()
            let uniqueIDs = ids.filter { seen.insert($0).inserted }
            guard !uniqueIDs.isEmpty else { return }

            var regularCandidates = Set<UUID>()
            for id in uniqueIDs {
                if dependencies.retireShortcutTabIfPresent(id) {
                    continue
                }
                dependencies.cancelRuntimeStatePersistence(id)
                if dependencies.removeTransientExtensionTab(id) {
                    continue
                }
                if dependencies.closeAuxiliaryMiniWindowTabIfPresent(id) {
                    continue
                }
                regularCandidates.insert(id)
            }

            let currentTabAtStart = dependencies.currentTab()
            let removals = dependencies.removeRegularTabs(
                regularCandidates,
                dependencies.spaces(),
                dependencies.currentSpace()?.id
            )
            guard !removals.isEmpty else { return }

            let runtimePorts = dependencies.requireRuntimePorts()
            let removedTabIDs = Set(removals.map(\.tab.id))
            runtimePorts.handleTabClosures(removedTabIDs)

            for removal in removals {
                let tab = removal.tab
                runtimePorts.notifyTabClosedIfLoaded(tab)

                runtimePorts.forEachWindowState { windowState in
                    windowState.selectionHistory
                        .removeFromRegularTabHistory(tab.id)
                }

                runtimePorts.webViewLifecycle.unloadTab(tab)
                runtimePorts.webViewLifecycle.requireRemoveAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: true
                )
                dependencies.detach(tab)

                NotificationCenter.default.post(
                    name: .sumiTabLifecycleDidChange,
                    object: tab
                )
            }

            if let currentTabAtStart,
               let currentRemoval = removals.first(where: {
                   $0.tab.id == currentTabAtStart.id
               }) {
                updateCurrentTabAfterRemovingCurrentTab(
                    currentRemoval.tab,
                    removedIndexInCurrentSpace:
                        currentRemoval.indexInCurrentSpace
                )
            }

            captureRecentlyClosedTabs(
                removals.map { ($0.tab, $0.spaceId) },
                count: removals.count
            )
            dependencies.scheduleStructuralPersistence()
            _ = runtimePorts.validateWindowStates()
        }
    }

    private func updateCurrentTabAfterRemovingCurrentTab(
        _ tab: Tab,
        removedIndexInCurrentSpace: Int?
    ) {
        if tab.spaceId == nil {
            updateCurrentTabAfterRemovingGlobalPinnedTab()
        } else if let currentSpace = dependencies.currentSpace() {
            updateCurrentTabAfterRemovingSpaceTab(
                in: currentSpace,
                removedIndexInCurrentSpace: removedIndexInCurrentSpace
            )
        }
    }

    private func updateCurrentTabAfterRemovingGlobalPinnedTab() {
        let pinnedTabs = dependencies.activeEssentialTabs(dependencies.currentProfileId())
        if !pinnedTabs.isEmpty {
            dependencies.replaceCurrentTab(pinnedTabs.last)
        } else if let currentSpace = dependencies.currentSpace() {
            let spacePinnedTabs = dependencies.liveSpacePinnedTabs(currentSpace.id)
            let regularTabs = dependencies.regularTabs(currentSpace.id)
            dependencies.replaceCurrentTab(spacePinnedTabs.last ?? regularTabs.last)
        } else {
            dependencies.replaceCurrentTab(nil)
        }
    }

    private func updateCurrentTabAfterRemovingSpaceTab(
        in currentSpace: Space,
        removedIndexInCurrentSpace: Int?
    ) {
        let spacePinnedTabs = dependencies.liveSpacePinnedTabs(currentSpace.id)
        let regularTabs = dependencies.regularTabs(currentSpace.id)
        let pinnedTabs = dependencies.activeEssentialTabs(dependencies.currentProfileId())

        if let removedIndexInCurrentSpace {
            let allSpaceTabs = spacePinnedTabs + regularTabs
            if !allSpaceTabs.isEmpty {
                let newIndex = min(removedIndexInCurrentSpace, allSpaceTabs.count - 1)
                dependencies.replaceCurrentTab(
                    allSpaceTabs.indices.contains(newIndex)
                        ? allSpaceTabs[newIndex]
                        : allSpaceTabs.first
                )
            } else if !pinnedTabs.isEmpty {
                dependencies.replaceCurrentTab(pinnedTabs.last)
            } else {
                dependencies.replaceCurrentTab(nil)
            }
        } else {
            dependencies.replaceCurrentTab(
                regularTabs.last
                    ?? spacePinnedTabs.last
                    ?? pinnedTabs.last
            )
        }
    }

    // MARK: - Closure Undo Capture

    private func captureRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        for (tab, spaceId) in tabs {
            dependencies.captureClosedTab(tab, spaceId)
        }

        dependencies.notifications()?.presentTabClosureNotification(tabCount: count)
    }

    // MARK: - Bulk Removal

    func closeAllTabsBelow(_ tab: Tab) {
        guard tab.spaceId != nil,
              let tabsBelow = dependencies.tabsBelow(tab),
              !tabsBelow.isEmpty else {
            return
        }
        removeTabs(tabsBelow.map(\.id))
    }

    func clearRegularTabs(for spaceId: UUID) {
        let tabs = dependencies.regularTabs(spaceId)
        guard !tabs.isEmpty else { return }

        RuntimeDiagnostics.emit("🧹 [TabRemovalOwner] Clearing \(tabs.count) regular tabs for space \(spaceId)")

        let inactiveRegular = tabs.filter {
            $0.id != dependencies.currentTab()?.id
        }
        if !inactiveRegular.isEmpty {
            removeTabs(inactiveRegular.map(\.id))
            return
        }
        if let active = dependencies.currentTab(),
           active.spaceId == spaceId,
           tabs.contains(where: { $0.id == active.id }) {
            removeTabs([active.id])
        }
    }
}

extension TabRemovalOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            requireRuntimePorts: { [weak tabManager] in
                guard let tabManager else {
                    preconditionFailure("TabManager dependency used after deallocation")
                }
                return tabManager.requireRuntimePorts()
            },
            cancelRuntimeStatePersistence: { [weak tabManager] tabId in
                tabManager?.structuralPersistence.cancelRuntimeStatePersistence(for: tabId)
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            removeTransientExtensionTab: { [weak tabManager] tabId in
                tabManager?.transientWebKitTabLifecycleOwner.removeTransientExtensionTab(id: tabId) ?? false
            },
            closeAuxiliaryMiniWindowTabIfPresent: { [weak tabManager] tabId in
                tabManager?.transientWebKitTabLifecycleOwner.closeAuxiliaryMiniWindowTabIfPresent(id: tabId) ?? false
            },
            removeRegularTabs: {
                [weak tabManager] tabIds, spaces, currentSpaceId in
                tabManager?.regularTabCollectionOwner.remove(
                    tabIds,
                    in: spaces,
                    currentSpaceId: currentSpaceId
                ) ?? []
            },
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            currentSpace: { [weak tabManager] in
                tabManager?.spaceStateOwner.currentSpace
            },
            retireShortcutTabIfPresent: { [weak tabManager] tabId in
                tabManager?.shortcutLiveTabRetirement.retire(tabId: tabId) != nil
            },
            detach: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.detach(tab)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner.activeEssentialTabs(for: profileId) ?? []
            },
            currentProfileId: { [weak tabManager] in
                tabManager?.runtimePorts?.currentProfileId
            },
            liveSpacePinnedTabs: { [weak tabManager] spaceId in
                tabManager?.shortcutPresentationOwner.liveSpacePinnedTabs(for: spaceId) ?? []
            },
            regularTabs: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            captureClosedTab: { [weak tabManager] tab, spaceId in
                tabManager?.runtimePorts?.captureClosedTab(tab, sourceSpaceId: spaceId)
            },
            notifications: { [weak tabManager] in
                tabManager?.runtimePorts?.notifications()
            },
            tabsBelow: { [weak tabManager] tab in
                tabManager?.regularTabCollectionOwner.tabsBelow(tab)
            }
        )
    }
}
