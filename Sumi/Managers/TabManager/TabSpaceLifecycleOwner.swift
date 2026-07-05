import Foundation

/// Owns space lifecycle mutations: creation, removal, reordering, renaming,
/// icon updates, and current-space activation with tab selection handoff.
@MainActor
final class TabSpaceLifecycleOwner {
    struct Dependencies {
        let withStructuralUpdateTransactionReturningSpace: (@MainActor () -> Space) -> Space
        let withStructuralUpdateTransactionVoid: (@MainActor () -> Void) -> Void
        let withStructuralUpdateTransactionBool: (@MainActor () -> Bool) -> Bool
        let withStructuralUpdateTransactionThrowingVoid: (@MainActor () throws -> Void) throws -> Void
        let defaultProfileId: () -> UUID?
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let sendObjectWillChange: () -> Void
        let markAllSpacesStructurallyDirty: () -> Void
        let setTabs: ([Tab], UUID) -> Void
        let scheduleStructuralPersistence: () -> Void
        let regularTabs: (UUID) -> [Tab]
        let transientShortcutTabs: (UUID) -> [Tab]
        let currentTab: () -> Tab?
        let replaceCurrentTab: (Tab?) -> Void
        let markSpaceStructurallyDeleted: (UUID) -> Void
        let removeFolders: (UUID) -> Void
        let setSpacePinnedShortcuts: ([ShortcutPin], UUID) -> Void
        let markFoldersSnapshotDirty: (UUID) -> Void
        let markSpacePinnedSnapshotDirty: (UUID) -> Void
        let removeTransientShortcutTabs: (UUID) -> Void
        let notifyTransientShortcutStateChanged: () -> Void
        let validateWindowStates: () -> Void
        let assignSpaceProfile: (UUID, UUID) -> Void
        let markSpacesSnapshotDirty: () -> Void
        let projection: (UUID, UUID?) -> SpaceLauncherProjectionSnapshot
        let spacePinnedPins: (UUID) -> [ShortcutPin]
        let activeEssentialTabs: (UUID?) -> [Tab]
        let currentProfileId: () -> UUID?
        let persistSelection: () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String = SumiPersistentGlyph.spaceDefaultIconValue,
        workspaceTheme: WorkspaceTheme? = nil,
        profileId: UUID? = nil
    ) -> Space {
        dependencies.withStructuralUpdateTransactionReturningSpace {
            let resolvedProfileId = profileId
                ?? dependencies.defaultProfileId()
            let defaultTheme = SumiWorkspaceThemePresets.rotatingTheme(
                at: dependencies.spaceStateOwner.count
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

            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.append(space)
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.setTabs([], space.id)

            if dependencies.spaceStateOwner.currentSpace == nil {
                dependencies.spaceStateOwner.replaceCurrentSpace(space)
            } else {
                setActiveSpace(space, preferredTab: nil, contextWindowId: nil)
            }
            dependencies.scheduleStructuralPersistence()
            return space
        }
    }

    func removeSpace(_ id: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard dependencies.spaceStateOwner.count > 1 else { return }
            guard let idx = dependencies.spaceStateOwner.index(of: id) else { return }

            let closing = dependencies.regularTabs(id)
            let transientClosing = dependencies.transientShortcutTabs(id)

            for tab in closing + transientClosing where dependencies.currentTab()?.id == tab.id {
                dependencies.replaceCurrentTab(nil)
            }

            dependencies.setTabs([], id)
            dependencies.markSpaceStructurallyDeleted(id)
            dependencies.sendObjectWillChange()
            dependencies.removeFolders(id)
            dependencies.setSpacePinnedShortcuts([], id)
            dependencies.markFoldersSnapshotDirty(id)
            dependencies.markSpacePinnedSnapshotDirty(id)
            dependencies.removeTransientShortcutTabs(id)
            dependencies.notifyTransientShortcutStateChanged()

            if idx < dependencies.spaceStateOwner.count {
                dependencies.sendObjectWillChange()
                dependencies.spaceStateOwner.remove(at: idx)
                dependencies.markAllSpacesStructurallyDirty()
            }

            if dependencies.spaceStateOwner.currentSpaceId == id {
                dependencies.spaceStateOwner.replaceCurrentSpace(dependencies.spaceStateOwner.firstSpace)
            }

            dependencies.scheduleStructuralPersistence()
            dependencies.validateWindowStates()
        }
    }

    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        dependencies.withStructuralUpdateTransactionBool {
            guard dependencies.spaceStateOwner.count > 1,
                  dependencies.spaceStateOwner.index(of: spaceId) != nil
            else {
                return false
            }

            dependencies.sendObjectWillChange()
            guard dependencies.spaceStateOwner.reorderSpace(
                spaceId: spaceId,
                to: targetIndex
            ) else {
                return false
            }

            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
            return true
        }
    }

    func setActiveSpace(
        _ space: Space,
        preferredTab: Tab? = nil,
        contextWindowId: UUID? = nil
    ) {
        guard dependencies.spaceStateOwner.contains(spaceId: space.id) else { return }

        if space.profileId == nil {
            let defaultProfileId = dependencies.defaultProfileId()
            if let profileId = defaultProfileId {
                dependencies.assignSpaceProfile(space.id, profileId)
            } else {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to a space switch target; reconciliation deferred.",
                    category: "TabManager"
                )
            }
        }

        let previousTab = dependencies.currentTab()
        let previousSpace = dependencies.spaceStateOwner.currentSpace

        if let previousSpace, let previousTab {
            previousSpace.activeTabId = previousTab.id
            dependencies.markSpacesSnapshotDirty()
        }

        dependencies.spaceStateOwner.replaceCurrentSpace(space)

        let projection = dependencies.projection(space.id, contextWindowId)
        let regularTabs = projection.regularTabs
        let persistedPins = dependencies.spacePinnedPins(space.id)
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
            let pinnedTabs = dependencies.activeEssentialTabs(dependencies.currentProfileId())
            if targetTab == nil, let match = regularTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if targetTab == nil, let match = spacePinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if targetTab == nil, let match = pinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            }
        }

        if targetTab == nil {
            if let currentTab = dependencies.currentTab(), currentTab.spaceId == space.id {
                targetTab = currentTab
            } else {
                let pinnedTabs = dependencies.activeEssentialTabs(dependencies.currentProfileId())
                targetTab = regularTabs.first ?? spacePinnedTabs.first ?? pinnedTabs.first
            }
        }

        let isTabChanging = targetTab?.id != dependencies.currentTab()?.id
        if isTabChanging {
            dependencies.replaceCurrentTab(targetTab)
        }

        if targetTab?.id == space.activeTabId {
            dependencies.markSpacesSnapshotDirty()
        }
        dependencies.persistSelection()
    }

    func resolvedTargetSpace(preferred space: Space?, fallbackSpaceId: UUID? = nil) -> Space {
        space
            ?? fallbackSpaceId.flatMap { spaceId in
                dependencies.spaceStateOwner.space(with: spaceId)
            }
            ?? ensureDefaultSpaceIfNeeded()
    }

    @discardableResult
    func backfillTargetSpaceProfileIfNeeded(
        _ targetSpace: Space,
        profileId: UUID?
    ) -> Bool {
        guard targetSpace.profileId == nil, let profileId else { return false }
        targetSpace.profileId = profileId
        dependencies.markAllSpacesStructurallyDirty()
        return true
    }

    @discardableResult
    func backfillTargetSpaceBootstrapProfileIfNeeded(_ targetSpace: Space) -> Bool {
        backfillTargetSpaceProfileIfNeeded(
            targetSpace,
            profileId: defaultProfileIdForSpaceBootstrap
        )
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        try dependencies.withStructuralUpdateTransactionThrowingVoid {
            guard dependencies.spaceStateOwner.space(with: spaceId) != nil else {
                throw TabManager.TabManagerError.spaceNotFound(spaceId)
            }

            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.renameSpace(spaceId: spaceId, to: newName)
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try dependencies.withStructuralUpdateTransactionThrowingVoid {
            guard dependencies.spaceStateOwner.space(with: spaceId) != nil else {
                throw TabManager.TabManagerError.spaceNotFound(spaceId)
            }

            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.updateIcon(spaceId: spaceId, to: icon)
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
        }
    }

    private var defaultProfileIdForSpaceBootstrap: UUID? {
        dependencies.currentProfileId() ?? dependencies.defaultProfileId()
    }

    // Ensure a deterministic default target space exists without inheriting process-global selection.
    private func ensureDefaultSpaceIfNeeded() -> Space {
        let profileId = defaultProfileIdForSpaceBootstrap
        if let profileId,
           let profileSpace = dependencies.spaceStateOwner.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        if let profileId,
           let unassignedSpace = dependencies.spaceStateOwner.first(where: { $0.profileId == nil }) {
            dependencies.sendObjectWillChange()
            dependencies.spaceStateOwner.assignProfile(spaceId: unassignedSpace.id, profileId: profileId)
            dependencies.markAllSpacesStructurallyDirty()
            dependencies.scheduleStructuralPersistence()
            return unassignedSpace
        }

        if profileId == nil,
           let firstSpace = dependencies.spaceStateOwner.firstSpace {
            return firstSpace
        }

        let personal = Space(
            name: "Personal",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            workspaceTheme: .default,
            profileId: profileId
        )
        dependencies.sendObjectWillChange()
        dependencies.spaceStateOwner.append(personal)
        dependencies.markAllSpacesStructurallyDirty()
        dependencies.setTabs([], personal.id)
        if dependencies.spaceStateOwner.currentSpace == nil {
            dependencies.spaceStateOwner.replaceCurrentSpace(personal)
        }
        dependencies.scheduleStructuralPersistence()
        return personal
    }
}

extension TabSpaceLifecycleOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransactionReturningSpace: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.withStructuralUpdateTransaction(operation)
            },
            withStructuralUpdateTransactionBool: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            withStructuralUpdateTransactionThrowingVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    try operation()
                    return
                }
                try tabManager.withStructuralUpdateTransaction(operation)
            },
            defaultProfileId: { [weak tabManager] in
                tabManager?.runtimeContext?.defaultProfileId
            },
            spaceStateOwner: tabManager.spaceStateOwner,
            sendObjectWillChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            markAllSpacesStructurallyDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markAllSpacesStructurallyDirty()
            },
            setTabs: { [weak tabManager] tabs, spaceId in
                tabManager?.structuralCollectionMutationOwner.setTabs(tabs, for: spaceId)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            regularTabs: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            transientShortcutTabs: { [weak tabManager] spaceId in
                tabManager?.transientTabRegistryOwner.transientShortcutTabs(inSpace: spaceId) ?? []
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            markSpaceStructurallyDeleted: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markSpaceStructurallyDeleted(spaceId)
            },
            removeFolders: { [weak tabManager] spaceId in
                tabManager?.folderCollectionStateOwner.removeFolders(for: spaceId)
            },
            setSpacePinnedShortcuts: { [weak tabManager] pins, spaceId in
                tabManager?.structuralCollectionMutationOwner.setSpacePinnedShortcuts(pins, for: spaceId)
            },
            markFoldersSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markFoldersSnapshotDirty(for: spaceId)
            },
            markSpacePinnedSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markSpacePinnedSnapshotDirty(for: spaceId)
            },
            removeTransientShortcutTabs: { [weak tabManager] spaceId in
                tabManager?.transientTabRegistryOwner.removeTransientShortcutTabs(inSpace: spaceId)
            },
            notifyTransientShortcutStateChanged: { [weak tabManager] in
                tabManager?.notifyTransientShortcutStateChanged()
            },
            validateWindowStates: { [weak tabManager] in
                tabManager?.runtimeContext?.validateWindowStates()
            },
            assignSpaceProfile: { [weak tabManager] spaceId, profileId in
                tabManager?.profileAssignmentOwner.assign(spaceId: spaceId, toProfile: profileId)
            },
            markSpacesSnapshotDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markSpacesSnapshotDirty()
            },
            projection: { [weak tabManager] spaceId, windowId in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.spaceLauncherProjectionOwner.projection(for: spaceId, in: windowId)
            },
            spacePinnedPins: { [weak tabManager] spaceId in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId) ?? []
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner.activeEssentialTabs(for: profileId) ?? []
            },
            currentProfileId: { [weak tabManager] in
                tabManager?.runtimeContext?.currentProfileId
            },
            persistSelection: { [weak tabManager] in
                tabManager?.structuralPersistence.persistSelection()
            }
        )
    }
}
