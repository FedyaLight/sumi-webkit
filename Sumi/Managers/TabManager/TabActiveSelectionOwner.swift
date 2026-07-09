import Foundation

@MainActor
final class TabActiveSelectionOwner {
    struct Dependencies {
        let contains: @MainActor (Tab) -> Bool
        let currentTab: @MainActor () -> Tab?
        let replaceCurrentTab: @MainActor (Tab?) -> Void
        let runtimePorts: @MainActor () -> RuntimePortRegistry?
        let spaces: @MainActor () -> [Space]
        let currentSpace: @MainActor () -> Space?
        let replaceCurrentSpace: @MainActor (Space?) -> Void
        let markSpacesSnapshotDirty: @MainActor () -> Void
        let persistSelection: @MainActor () -> Void
        let windowState: @MainActor (UUID) -> BrowserWindowState?
        let currentSpaceId: @MainActor () -> UUID?
        let profileIdForSpace: @MainActor (UUID) -> UUID?
        let currentProfileId: @MainActor () -> UUID?
        let regularTabs: @MainActor (UUID) -> [Tab]
        let activeEssentialTabs: @MainActor (UUID?) -> [Tab]
        let activeShortcutTab: @MainActor (UUID) -> Tab?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func setActiveTab(_ tab: Tab) {
        guard dependencies.contains(tab) else {
            return
        }
        let previous = dependencies.currentTab()
        if previous?.id != tab.id {
            dependencies.replaceCurrentTab(tab)
        }

        updateActiveSplitSelection(for: tab)
        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: false)

        if previous?.id != tab.id {
            dependencies.runtimePorts()?.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: previous
            )
        }

        dependencies.persistSelection()
    }

    /// Update only the global tab state without triggering UI operations.
    /// Used when BrowserManager.selectTab() has already handled all UI concerns.
    func updateActiveTabState(_ tab: Tab) {
        guard dependencies.contains(tab) else {
            return
        }
        dependencies.replaceCurrentTab(tab)
        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: true)

        dependencies.persistSelection()
    }

    func selectionTabsForCurrentContext(in windowId: UUID? = nil) -> [Tab] {
        let contextWindowState = windowId.flatMap { dependencies.windowState($0) }
        let contextSpaceId = contextWindowState?.currentSpaceId ?? dependencies.currentSpaceId()
        let contextProfileId =
            contextWindowState?.currentProfileId
            ?? contextSpaceId.flatMap { dependencies.profileIdForSpace($0) }
            ?? dependencies.currentProfileId()
        let regularTabs = contextSpaceId.map { dependencies.regularTabs($0) } ?? []
        let activeLauncherTab = windowId
            .flatMap { dependencies.activeShortcutTab($0) }
            .flatMap { liveTab -> Tab? in
                guard liveTab.shortcutPinRole != .essential else { return nil }
                guard liveTab.spaceId == nil || liveTab.spaceId == contextSpaceId else { return nil }
                return liveTab
            }

        return dependencies.activeEssentialTabs(contextProfileId) + (activeLauncherTab.map { [$0] } ?? []) + regularTabs
    }

    private func updateActiveSplitSelection(for tab: Tab) {
        guard let runtimePorts = dependencies.runtimePorts() else { return }
        runtimePorts.forEachWindow { windowId, windowState in
            if runtimePorts.visibleSplitTabIds(for: windowId).contains(tab.id) {
                runtimePorts.updateActiveSplitSide(for: tab.id, in: windowId)
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
           let space = dependencies.spaces().first(where: { $0.id == spaceId }) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
            if refreshCurrentSpaceReference || dependencies.currentSpace()?.id != space.id {
                dependencies.replaceCurrentSpace(space)
            }
        } else if let currentSpace = dependencies.currentSpace() {
            if currentSpace.activeTabId != tab.id {
                currentSpace.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
        }
        if didChangeSpacePersistenceState {
            dependencies.markSpacesSnapshotDirty()
        }
    }
}

extension TabActiveSelectionOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            contains: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.contains(tab) ?? false
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            runtimePorts: { [weak tabManager] in
                tabManager?.runtimePorts
            },
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            currentSpace: { [weak tabManager] in
                tabManager?.spaceStateOwner.currentSpace
            },
            replaceCurrentSpace: { [weak tabManager] space in
                tabManager?.spaceStateOwner.replaceCurrentSpace(space)
            },
            markSpacesSnapshotDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markSpacesSnapshotDirty()
            },
            persistSelection: { [weak tabManager] in
                tabManager?.structuralPersistence.persistSelection()
            },
            windowState: { [weak tabManager] windowId in
                tabManager?.runtimePorts?.windowState(for: windowId)
            },
            currentSpaceId: { [weak tabManager] in
                tabManager?.spaceStateOwner.currentSpaceId
            },
            profileIdForSpace: { [weak tabManager] spaceId in
                tabManager?.spaceStateOwner.profileId(for: spaceId)
            },
            currentProfileId: { [weak tabManager] in
                tabManager?.runtimePorts?.currentProfileId
            },
            regularTabs: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner.activeEssentialTabs(for: profileId) ?? []
            },
            activeShortcutTab: { [weak tabManager] windowId in
                tabManager?.shortcutPresentationOwner.activeShortcutTab(for: windowId)
            }
        )
    }
}
