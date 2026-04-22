import Foundation

extension TabManager {
    func userVisibleTabCount(for spaceId: UUID) -> Int {
        launcherProjection(for: spaceId).userVisibleTabCount
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String = "square.grid.2x2",
        gradient: SpaceGradient = .default,
        profileId: UUID? = nil
    ) -> Space {
        return withStructuralUpdateTransaction {
            let resolvedProfileId = profileId
                ?? browserManager?.currentProfile?.id
                ?? browserManager?.profileManager.profiles.first?.id
            let defaultTheme = SumiWorkspaceThemePresets.rotatingTheme(at: spaces.count)
            let resolvedTheme: WorkspaceTheme
            if gradient.visuallyEquals(.default) {
                resolvedTheme = defaultTheme
            } else {
                resolvedTheme = WorkspaceTheme(
                    gradient: gradient
                )
            }

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

            spaces.append(space)
            markAllSpacesStructurallyDirty()
            setTabs([], for: space.id)

            if currentSpace == nil {
                currentSpace = space
            } else {
                setActiveSpace(space)
            }
            scheduleStructuralPersistence()
            return space
        }
    }

    func removeSpace(_ id: UUID) {
        withStructuralUpdateTransaction {
            guard spaces.count > 1 else { return }
            guard let idx = spaces.firstIndex(where: { $0.id == id }) else { return }

            let closing = tabsBySpace[id] ?? []
            let transientClosing = transientShortcutTabsByWindow.values
                .flatMap(\.values)
                .filter { $0.spaceId == id }

            for tab in closing + transientClosing where currentTab?.id == tab.id {
                currentTab = nil
            }

            setTabs([], for: id)
            markSpaceStructurallyDeleted(id)
            foldersBySpace.removeValue(forKey: id)
            spacePinnedShortcuts.removeValue(forKey: id)
            markFoldersSnapshotDirty(for: id)
            markSpacePinnedSnapshotDirty(for: id)
            transientShortcutTabsByWindow = transientShortcutTabsByWindow.compactMapValues { tabsByPin in
                let filtered = tabsByPin.filter { _, tab in tab.spaceId != id }
                return filtered.isEmpty ? nil : filtered
            }
            notifyTransientShortcutStateChanged()

            if idx < spaces.count {
                spaces.remove(at: idx)
                markAllSpacesStructurallyDirty()
            }

            if currentSpace?.id == id {
                currentSpace = spaces.first
            }

            scheduleStructuralPersistence()
            browserManager?.validateWindowStates()
        }
    }

    func setActiveSpace(_ space: Space, preferredTab: Tab? = nil) {
        guard spaces.contains(where: { $0.id == space.id }) else { return }

        if space.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id
                ?? browserManager?.profileManager.profiles.first?.id
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
            in: browserManager?.windowRegistry?.activeWindow?.id
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
            guard let idx = spaces.firstIndex(where: { $0.id == spaceId }), idx < spaces.count else {
                throw TabManagerError.spaceNotFound(spaceId)
            }

            spaces[idx].name = newName
            if currentSpace?.id == spaceId {
                currentSpace?.name = newName
            }
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try withStructuralUpdateTransaction {
            guard let idx = spaces.firstIndex(where: { $0.id == spaceId }), idx < spaces.count else {
                throw TabManagerError.spaceNotFound(spaceId)
            }

            let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(icon)
            spaces[idx].icon = normalized
            if currentSpace?.id == spaceId {
                currentSpace?.icon = normalized
            }
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
        }
    }
}
