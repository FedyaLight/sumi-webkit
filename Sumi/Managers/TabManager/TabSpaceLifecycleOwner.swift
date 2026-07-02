import Foundation

/// Owns space lifecycle mutations: creation, removal, reordering, renaming,
/// icon updates, and current-space activation with tab selection handoff.
@MainActor
final class TabSpaceLifecycleOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String,
        workspaceTheme: WorkspaceTheme?,
        profileId: UUID?
    ) -> Space {
        tabManager.withStructuralUpdateTransaction {
            let resolvedProfileId = profileId
                ?? tabManager.runtimeContext?.defaultProfileId
            let defaultTheme = SumiWorkspaceThemePresets.rotatingTheme(
                at: tabManager.spaceCollectionStateOwner.count
            )
            let resolvedTheme = workspaceTheme ?? defaultTheme

            let space = Space(
                name: name,
                icon: icon,
                workspaceTheme: resolvedTheme,
                profileId: resolvedProfileId
            )

            if resolvedProfileId == nil {
                RuntimeDiagnostics.debug(
                    "Creating space '\(name)' without a resolved profile; profile reconciliation will run later.",
                    category: "TabManager"
                )
            }

            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.append(space)
            tabManager.markAllSpacesStructurallyDirty()
            tabManager.setTabs([], for: space.id)

            if tabManager.spaceCollectionStateOwner.currentSpace == nil {
                tabManager.spaceCollectionStateOwner.replaceCurrentSpace(space)
            } else {
                setActiveSpace(space, preferredTab: nil, contextWindowId: nil)
            }
            tabManager.scheduleStructuralPersistence()
            return space
        }
    }

    func removeSpace(_ id: UUID) {
        tabManager.withStructuralUpdateTransaction {
            guard tabManager.spaceCollectionStateOwner.count > 1 else { return }
            guard let idx = tabManager.spaceCollectionStateOwner.index(of: id) else { return }

            let closing = tabManager.regularTabCollectionOwner.tabs(in: id)
            let transientClosing = tabManager.transientTabRegistryOwner
                .transientShortcutTabs(inSpace: id)

            for tab in closing + transientClosing where tabManager.currentTab?.id == tab.id {
                tabManager.currentTab = nil
            }

            tabManager.setTabs([], for: id)
            tabManager.markSpaceStructurallyDeleted(id)
            tabManager.objectWillChange.send()
            tabManager.folderCollectionStateOwner.removeFolders(for: id)
            tabManager.spacePinnedShortcuts.removeValue(forKey: id)
            tabManager.markFoldersSnapshotDirty(for: id)
            tabManager.markSpacePinnedSnapshotDirty(for: id)
            tabManager.transientTabRegistryOwner.removeTransientShortcutTabs(inSpace: id)
            tabManager.notifyTransientShortcutStateChanged()

            if idx < tabManager.spaceCollectionStateOwner.count {
                tabManager.objectWillChange.send()
                tabManager.spaceCollectionStateOwner.remove(at: idx)
                tabManager.markAllSpacesStructurallyDirty()
            }

            if tabManager.spaceCollectionStateOwner.currentSpaceId == id {
                tabManager.currentSpace = tabManager.spaceCollectionStateOwner.firstSpace
            }

            tabManager.scheduleStructuralPersistence()
            tabManager.runtimeContext?.validateWindowStates()
        }
    }

    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            guard tabManager.spaceCollectionStateOwner.count > 1,
                  tabManager.spaceCollectionStateOwner.index(of: spaceId) != nil
            else {
                return false
            }

            tabManager.objectWillChange.send()
            guard tabManager.spaceCollectionStateOwner.reorderSpace(
                spaceId: spaceId,
                to: targetIndex
            ) else {
                return false
            }

            tabManager.markAllSpacesStructurallyDirty()
            tabManager.scheduleStructuralPersistence()
            return true
        }
    }

    func setActiveSpace(
        _ space: Space,
        preferredTab: Tab?,
        contextWindowId: UUID?
    ) {
        guard tabManager.spaceCollectionStateOwner.contains(spaceId: space.id) else { return }

        if space.profileId == nil {
            let defaultProfileId = tabManager.runtimeContext?.defaultProfileId
            if let profileId = defaultProfileId {
                tabManager.assign(spaceId: space.id, toProfile: profileId)
            } else {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to a space switch target; reconciliation deferred.",
                    category: "TabManager"
                )
            }
        }

        let previousTab = tabManager.currentTab
        let previousSpace = tabManager.currentSpace

        if let previousSpace, let previousTab {
            previousSpace.activeTabId = previousTab.id
            tabManager.markSpacesSnapshotDirty()
        }

        tabManager.currentSpace = space

        let projection = tabManager.launcherProjection(
            for: space.id,
            in: contextWindowId
        )
        let regularTabs = projection.regularTabs
        let persistedPins = tabManager.spacePinnedPins(for: space.id)
        let spacePinnedTabs = projection.liveTabsByPinId.values.sorted { lhs, rhs in
            let leftOrder = lhs.shortcutPinId.flatMap { pinId in
                persistedPins.first(where: { $0.id == pinId })?.index
            } ?? lhs.index
            let rightOrder = rhs.shortcutPinId.flatMap { pinId in
                persistedPins.first(where: { $0.id == pinId })?.index
            } ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var targetTab: Tab?
        if let preferredTab {
            let belongsToSpace = preferredTab.spaceId == space.id
            let isGlobalPinned = preferredTab.isPinned
            let isSpacePinnedForSpace = preferredTab.isSpacePinned && preferredTab.spaceId == space.id
            if belongsToSpace || isGlobalPinned || isSpacePinnedForSpace {
                targetTab = preferredTab
            }
        }

        if let activeId = space.activeTabId {
            if targetTab == nil, let match = regularTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if targetTab == nil, let match = spacePinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if targetTab == nil, let match = tabManager.pinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            }
        }

        if targetTab == nil {
            if let currentTab = tabManager.currentTab, currentTab.spaceId == space.id {
                targetTab = currentTab
            } else {
                targetTab = regularTabs.first ?? spacePinnedTabs.first ?? tabManager.pinnedTabs.first
            }
        }

        let isTabChanging = targetTab?.id != tabManager.currentTab?.id
        if isTabChanging {
            tabManager.currentTab = targetTab
        }

        if targetTab?.id == space.activeTabId {
            tabManager.markSpacesSnapshotDirty()
        }
        tabManager.persistSelection()
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        try tabManager.withStructuralUpdateTransaction {
            guard tabManager.spaceCollectionStateOwner.space(with: spaceId) != nil else {
                throw TabManager.TabManagerError.spaceNotFound(spaceId)
            }

            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.renameSpace(spaceId: spaceId, to: newName)
            tabManager.markAllSpacesStructurallyDirty()
            tabManager.scheduleStructuralPersistence()
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try tabManager.withStructuralUpdateTransaction {
            guard tabManager.spaceCollectionStateOwner.space(with: spaceId) != nil else {
                throw TabManager.TabManagerError.spaceNotFound(spaceId)
            }

            tabManager.objectWillChange.send()
            tabManager.spaceCollectionStateOwner.updateIcon(spaceId: spaceId, to: icon)
            tabManager.markAllSpacesStructurallyDirty()
            tabManager.scheduleStructuralPersistence()
        }
    }
}
