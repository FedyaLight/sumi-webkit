import Foundation

extension TabManager {
    func userVisibleTabCount(for spaceId: UUID) -> Int {
        launcherProjection(for: spaceId).userVisibleTabCount
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String = "square.grid.2x2",
        workspaceTheme: WorkspaceTheme? = nil,
        profileId: UUID? = nil
    ) -> Space {
        withStructuralUpdateTransaction {
            let resolvedProfileId = profileId
                ?? runtimeContext?.defaultProfileId
            let defaultTheme = SumiWorkspaceThemePresets.rotatingTheme(at: spaceCollectionStateOwner.count)
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

            objectWillChange.send()
            spaceCollectionStateOwner.append(space)
            markAllSpacesStructurallyDirty()
            setTabs([], for: space.id)

            if spaceCollectionStateOwner.currentSpace == nil {
                spaceCollectionStateOwner.replaceCurrentSpace(space)
            } else {
                setActiveSpace(space)
            }
            scheduleStructuralPersistence()
            return space
        }
    }

    func removeSpace(_ id: UUID) {
        withStructuralUpdateTransaction {
            guard spaceCollectionStateOwner.count > 1 else { return }
            guard let idx = spaceCollectionStateOwner.index(of: id) else { return }

            let closing = regularTabCollectionOwner.tabs(in: id)
            let transientClosing = transientTabRegistryOwner
                .transientShortcutTabs(inSpace: id)

            for tab in closing + transientClosing where currentTab?.id == tab.id {
                currentTab = nil
            }

            setTabs([], for: id)
            markSpaceStructurallyDeleted(id)
            objectWillChange.send()
            folderCollectionStateOwner.removeFolders(for: id)
            spacePinnedShortcuts.removeValue(forKey: id)
            markFoldersSnapshotDirty(for: id)
            markSpacePinnedSnapshotDirty(for: id)
            transientTabRegistryOwner.removeTransientShortcutTabs(inSpace: id)
            notifyTransientShortcutStateChanged()

            if idx < spaceCollectionStateOwner.count {
                objectWillChange.send()
                spaceCollectionStateOwner.remove(at: idx)
                markAllSpacesStructurallyDirty()
            }

            if spaceCollectionStateOwner.currentSpaceId == id {
                currentSpace = spaceCollectionStateOwner.firstSpace
            }

            scheduleStructuralPersistence()
            runtimeContext?.validateWindowStates()
        }
    }

    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        withStructuralUpdateTransaction {
            guard spaceCollectionStateOwner.count > 1,
                  spaceCollectionStateOwner.index(of: spaceId) != nil
            else {
                return false
            }

            objectWillChange.send()
            guard spaceCollectionStateOwner.reorderSpace(spaceId: spaceId, to: targetIndex) else {
                return false
            }

            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
            return true
        }
    }

    func setActiveSpace(
        _ space: Space,
        preferredTab: Tab? = nil,
        contextWindowId: UUID? = nil
    ) {
        guard spaceCollectionStateOwner.contains(spaceId: space.id) else { return }

        if space.profileId == nil {
            let defaultProfileId = runtimeContext?.defaultProfileId
            if let profileId = defaultProfileId {
                assign(spaceId: space.id, toProfile: profileId)
            } else {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to a space switch target; reconciliation deferred.",
                    category: "TabManager"
                )
            }
        }

        let previousTab = currentTab
        let previousSpace = currentSpace

        if let previousSpace, let previousTab {
            previousSpace.activeTabId = previousTab.id
            markSpacesSnapshotDirty()
        }

        currentSpace = space

        let projection = launcherProjection(
            for: space.id,
            in: contextWindowId
        )
        let regularTabs = projection.regularTabs
        let persistedPins = spacePinnedPins(for: space.id)
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
            } else if targetTab == nil, let match = pinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            }
        }

        if targetTab == nil {
            if let currentTab, currentTab.spaceId == space.id {
                targetTab = currentTab
            } else {
                targetTab = regularTabs.first ?? spacePinnedTabs.first ?? pinnedTabs.first
            }
        }

        let isTabChanging = targetTab?.id != currentTab?.id
        if isTabChanging {
            currentTab = targetTab
        }

        if targetTab?.id == space.activeTabId {
            markSpacesSnapshotDirty()
        }
        persistSelection()
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        try withStructuralUpdateTransaction {
            guard spaceCollectionStateOwner.space(with: spaceId) != nil else {
                throw TabManagerError.spaceNotFound(spaceId)
            }

            objectWillChange.send()
            spaceCollectionStateOwner.renameSpace(spaceId: spaceId, to: newName)
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try withStructuralUpdateTransaction {
            guard spaceCollectionStateOwner.space(with: spaceId) != nil else {
                throw TabManagerError.spaceNotFound(spaceId)
            }

            objectWillChange.send()
            spaceCollectionStateOwner.updateIcon(spaceId: spaceId, to: icon)
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }
}
