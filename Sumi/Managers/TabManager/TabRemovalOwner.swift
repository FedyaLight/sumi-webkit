import Foundation

@MainActor
final class TabRemovalOwner {
    struct Dependencies {
        let withStructuralUpdateTransaction: (@MainActor () -> Void) -> Void
        let runtimePorts: () -> RuntimePortRegistry?
        let requireRuntimePorts: () -> RuntimePortRegistry
        let cancelRuntimeStatePersistence: (UUID) -> Void
        let currentTab: () -> Tab?
        let replaceCurrentTab: (Tab?) -> Void
        let removeTransientExtensionTab: (UUID) -> Bool
        let closeAuxiliaryMiniWindowTabIfPresent: (UUID) -> Bool
        let removeRegularTab: (UUID, [Space], UUID?) -> RegularTabCollectionOwner.Removal?
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
        let setActiveTab: (Tab) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func removeTab(_ id: UUID) {
        dependencies.withStructuralUpdateTransaction {
            if dependencies.retireShortcutTabIfPresent(id) {
                return
            }
            dependencies.runtimePorts()?.handleTabClosure(id)
            dependencies.cancelRuntimeStatePersistence(id)

            let wasCurrent = (dependencies.currentTab()?.id == id)
            var removed: Tab?
            var removedSpaceId: UUID?
            var removedIndexInCurrentSpace: Int?

            if dependencies.removeTransientExtensionTab(id) {
                return
            }

            if dependencies.closeAuxiliaryMiniWindowTabIfPresent(id) {
                return
            }

            if let removal = dependencies.removeRegularTab(
                id,
                dependencies.spaces(),
                dependencies.currentSpace()?.id
            ) {
                removed = removal.tab
                removedSpaceId = removal.spaceId
                removedIndexInCurrentSpace = removal.indexInCurrentSpace
            }
            guard let tab = removed else { return }
            let runtimePorts = dependencies.requireRuntimePorts()

            runtimePorts.notifyTabClosedIfLoaded(tab)

            runtimePorts.forEachWindowState { windowState in
                windowState.selectionHistory.removeFromRegularTabHistory(tab.id)
            }

            captureRecentlyClosedTab(tab, spaceId: removedSpaceId)

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

            if wasCurrent {
                updateCurrentTabAfterRemovingCurrentTab(
                    tab,
                    removedIndexInCurrentSpace: removedIndexInCurrentSpace
                )
            }

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

    func captureRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        dependencies.captureClosedTab(tab, spaceId)
        dependencies.notifications()?.presentTabClosureNotification(tabCount: 1)
    }

    private func captureRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        for (tab, spaceId) in tabs {
            dependencies.captureClosedTab(tab, spaceId)
        }

        dependencies.notifications()?.presentTabClosureNotification(tabCount: count)
    }

    // MARK: - Bulk Removal

    func closeAllTabsBelow(_ tab: Tab) {
        dependencies.withStructuralUpdateTransaction {
            guard let spaceId = tab.spaceId else { return }
            guard let tabsBelow = dependencies.tabsBelow(tab) else { return }
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

    func clearRegularTabs(for spaceId: UUID) {
        dependencies.withStructuralUpdateTransaction {
            let tabs = dependencies.regularTabs(spaceId)
            guard !tabs.isEmpty else { return }

            RuntimeDiagnostics.emit("🧹 [TabRemovalOwner] Clearing \(tabs.count) regular tabs for space \(spaceId)")

            let inactiveRegular = tabs.filter { $0.id != dependencies.currentTab()?.id }
            if !inactiveRegular.isEmpty {
                for tab in inactiveRegular {
                    removeTab(tab.id)
                }
                return
            }
            if let active = dependencies.currentTab(),
               active.spaceId == spaceId,
               tabs.contains(where: { $0.id == active.id }) {
                removeTab(active.id)
            }
        }
    }

    private func closeTabWithoutTracking(_ id: UUID) {
        dependencies.cancelRuntimeStatePersistence(id)
        let wasCurrent = dependencies.currentTab()?.id == id
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        if let removal = dependencies.removeRegularTab(
                id,
                dependencies.spaces(),
                dependencies.currentSpace()?.id
            ) {
            removed = removal.tab
            removedIndexInCurrentSpace = removal.indexInCurrentSpace
        }

        guard let tab = removed else { return }

        let runtimePorts = dependencies.requireRuntimePorts()
        runtimePorts.webViewLifecycle.unloadTab(tab)
        runtimePorts.webViewLifecycle.requireRemoveAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )

        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )

        if wasCurrent {
            if tab.spaceId == nil {
                let tabs = dependencies.activeEssentialTabs(runtimePorts.currentProfileId)
                if let first = tabs.first {
                    dependencies.setActiveTab(first)
                }
            } else if let spaceId = tab.spaceId {
                let spaceTabs = dependencies.regularTabs(spaceId)
                if !spaceTabs.isEmpty {
                    let targetIndex = min(removedIndexInCurrentSpace ?? 0, spaceTabs.count - 1)
                    dependencies.setActiveTab(spaceTabs[targetIndex])
                }
            }
        }

        dependencies.scheduleStructuralPersistence()
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
            runtimePorts: { [weak tabManager] in
                tabManager?.runtimePorts
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
            removeRegularTab: { [weak tabManager] tabId, spaces, currentSpaceId in
                tabManager?.regularTabCollectionOwner.remove(tabId, in: spaces, currentSpaceId: currentSpaceId)
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
            },
            setActiveTab: { [weak tabManager] tab in
                tabManager?.activeSelectionOwner.setActiveTab(tab)
            }
        )
    }
}
