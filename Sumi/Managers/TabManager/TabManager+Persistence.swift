import AppKit
import Foundation
import SwiftData

@MainActor
extension TabManager {
    public nonisolated func persistSnapshot() {
        Task { @MainActor [weak self] in
            self?.scheduleSnapshotPersistence()
        }
    }

    // Returns true if atomic path succeeded; false if fallback was used or stale.
    public nonisolated func persistSnapshotAwaitingResult() async -> Bool {
        await MainActor.run { [weak self] in
            self?.cancelScheduledSnapshotPersistence()
        }
        return await persistSnapshotNow()
    }

    private func scheduleSnapshotPersistence() {
        snapshotPersistRequestID &+= 1
        let requestID = snapshotPersistRequestID
        let debounceDelay = snapshotPersistDebounceNanoseconds

        scheduledSnapshotPersistTask?.cancel()
        scheduledSnapshotPersistTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }

            await self?.executeScheduledSnapshotPersistence(requestID: requestID)
        }
    }

    private func cancelScheduledSnapshotPersistence() {
        snapshotPersistRequestID &+= 1
        scheduledSnapshotPersistTask?.cancel()
        scheduledSnapshotPersistTask = nil
    }

    private func executeScheduledSnapshotPersistence(requestID: UInt64) async {
        guard snapshotPersistRequestID == requestID else { return }
        scheduledSnapshotPersistTask = nil
        _ = await persistSnapshotNow()
    }

    private nonisolated func persistSnapshotNow() async -> Bool {
        let payload: (TabSnapshotRepository.Snapshot, Int)? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            strong.snapshotGeneration &+= 1
            let generation = strong.snapshotGeneration
            // TODO(runtime): If Instruments still shows snapshot assembly as a hot path,
            // split this into per-space fragments keyed by structural generations.
            let snapshot = strong._buildSnapshot()
            return (snapshot, generation)
        }
        guard let (snapshot, generation) = payload else {
            return false
        }
        return await persistence.persist(snapshot: snapshot, generation: generation)
    }

    /// Lightweight persistence for tab selection changes only.
    /// Avoids rebuilding the full snapshot graph when only currentTabID/currentSpaceID changed.
    func persistSelection() {
        let tabID = currentTab?.id
        let spaceID = currentSpace?.id
        Task { [persistence] in
            await persistence.persistSelectionOnly(currentTabID: tabID, currentSpaceID: spaceID)
        }
    }

    func scheduleRuntimeStatePersistence(for tab: Tab) {
        guard shouldPersistRuntimeState(for: tab) else { return }

        let tabID = tab.id
        let debounceDelay = runtimeStatePersistDebounceNanoseconds
        pendingRuntimeStatePersistTasks[tabID]?.cancel()
        pendingRuntimeStatePersistTasks[tabID] = Task { [weak self, weak tab] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }

            guard let self, let tab else { return }
            self.pendingRuntimeStatePersistTasks.removeValue(forKey: tabID)
            await self.persistRuntimeStateNow(for: tab)
        }
    }

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        pendingRuntimeStatePersistTasks[tabId]?.cancel()
        pendingRuntimeStatePersistTasks.removeValue(forKey: tabId)
    }

    private func shouldPersistRuntimeState(for tab: Tab) -> Bool {
        guard tab.isShortcutLiveInstance == false else { return false }
        guard tab.isPinned == false, tab.isSpacePinned == false else { return false }
        return tab.spaceId != nil
    }

    private nonisolated func persistRuntimeStateNow(for tab: Tab) async {
        let payload: TabSnapshotRepository.RuntimeTabState? = await MainActor.run {
            guard self.shouldPersistRuntimeState(for: tab) else { return nil }
            return TabSnapshotRepository.RuntimeTabState(
                id: tab.id,
                urlString: tab.url.absoluteString,
                currentURLString: tab.url.absoluteString,
                name: tab.name,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
        }
        guard let payload else { return }
        await persistence.persistRuntimeState(payload)
    }

    func _buildSnapshot() -> TabSnapshotRepository.Snapshot {
        reconcileProfileRuntimeStates(activeSpaceId: currentSpace?.id)

        var spaceSnapshots: [TabSnapshotRepository.SnapshotSpace] = []
        spaceSnapshots.reserveCapacity(spaces.count)
        for (index, space) in spaces.enumerated() {
            let snapshot = TabSnapshotRepository.SnapshotSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                gradientData: space.gradient.encoded,
                workspaceThemeData: space.workspaceTheme.encoded,
                activeTabId: space.activeTabId,
                profileId: space.profileId
            )
            spaceSnapshots.append(snapshot)
        }

        var tabSnapshots: [TabSnapshotRepository.SnapshotTab] = []
        for (profileId, pins) in pinnedByProfile {
            let orderedPins = Array(pins).sorted { $0.index < $1.index }
            for (index, pin) in orderedPins.enumerated() {
                tabSnapshots.append(.init(
                    id: pin.id,
                    urlString: pin.launchURL.absoluteString,
                    name: pin.title,
                    index: index,
                    spaceId: nil,
                    isPinned: true,
                    isSpacePinned: false,
                    profileId: profileId,
                    folderId: nil,
                    iconAsset: pin.iconAsset,
                    currentURLString: pin.launchURL.absoluteString,
                    canGoBack: false,
                    canGoForward: false
                ))
            }
        }

        for space in spaces {
            let shortcutPins = Array(spacePinnedShortcuts[space.id] ?? []).sorted { $0.index < $1.index }
            for (index, pin) in shortcutPins.enumerated() {
                tabSnapshots.append(.init(
                    id: pin.id,
                    urlString: pin.launchURL.absoluteString,
                    name: pin.title,
                    index: index,
                    spaceId: space.id,
                    isPinned: false,
                    isSpacePinned: true,
                    profileId: nil,
                    folderId: pin.folderId,
                    iconAsset: pin.iconAsset,
                    currentURLString: pin.launchURL.absoluteString,
                    canGoBack: false,
                    canGoForward: false
                ))
            }

            let regularTabs = Array(tabsBySpace[space.id] ?? [])
            for (index, tab) in regularTabs.enumerated() {
                tabSnapshots.append(.init(
                    id: tab.id,
                    urlString: tab.url.absoluteString,
                    name: tab.name,
                    index: index,
                    spaceId: space.id,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    folderId: tab.folderId,
                    iconAsset: nil,
                    currentURLString: tab.url.absoluteString,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                ))
            }
        }

        var folderSnapshots: [TabSnapshotRepository.SnapshotFolder] = []
            for (spaceId, folders) in foldersBySpace {
                let orderedFolders = folders.sorted { $0.index < $1.index }
                for (index, folder) in orderedFolders.enumerated() {
                    folderSnapshots.append(.init(
                        id: folder.id,
                        name: folder.name,
                        icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon),
                        color: folder.color.toHexString() ?? "#000000",
                        spaceId: spaceId,
                        isOpen: folder.isOpen,
                        index: index
                    ))
            }
        }

        let state = TabSnapshotRepository.SnapshotState(
            currentTabID: currentTab?.id,
            currentSpaceID: currentSpace?.id
        )

        return TabSnapshotRepository.Snapshot(
            spaces: spaceSnapshots,
            tabs: tabSnapshots,
            folders: folderSnapshots,
            state: state
        )
    }

    func hasLiveRuntimeContent(in space: Space) -> Bool {
        let spaceId = space.id

        if !(tabsBySpace[spaceId] ?? []).isEmpty { return true }
        if !(spacePinnedShortcuts[spaceId] ?? []).isEmpty { return true }
        if !(foldersBySpace[spaceId] ?? []).isEmpty { return true }

        return transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .contains { $0.spaceId == spaceId }
    }

    func reconcileProfileRuntimeStates(activeSpaceId: UUID?) {
        for space in spaces {
            let hasRuntimeContent = hasLiveRuntimeContent(in: space)

            if space.id == activeSpaceId {
                space.profileRuntimeState = hasRuntimeContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasRuntimeContent ? .loadedInactive : .dormant
            }
        }
    }

    func loadFromStore() {
        markInitialDataLoadStarted()
        SidebarUITestDragMarker.recordEvent(
            "startupLoadBegin",
            dragItemID: nil,
            ownerDescription: "TabManager.loadFromStore",
            details: "storeLoadStarted=true"
        )
        defer {
            markInitialDataLoadFinished()
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        }

        do {
            let defaultRestoreURL = URL(string: "about:blank")!
            var needsSnapshotPersistence = false

            let spaceEntities = try context.fetch(
                FetchDescriptor<SpaceEntity>()
            )
            var didNormalizeSpaceIcons = false
            for entity in spaceEntities {
                let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(entity.icon)
                if normalized != entity.icon {
                    entity.icon = normalized
                    didNormalizeSpaceIcons = true
                }
            }
            if didNormalizeSpaceIcons {
                try context.save()
            }
            let sortedSpaces = spaceEntities.sorted { $0.index < $1.index }
            self.spaces = sortedSpaces.map { entity in
                let workspaceTheme: WorkspaceTheme
                workspaceTheme = WorkspaceTheme.decode(entity.workspaceThemeData ?? Data())
                    ?? WorkspaceTheme(
                        gradient: SpaceGradient.decode(entity.gradientData)
                    )
                return Space(
                    id: entity.id,
                    name: entity.name,
                    icon: entity.icon,
                    workspaceTheme: workspaceTheme,
                    profileId: entity.profileId
                )
            }
            for sp in spaces {
                setTabs([], for: sp.id)
            }

            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let dp = defaultProfileId {
                var didAssignProfiles = false
                for space in spaces where space.profileId == nil {
                    space.profileId = dp
                    didAssignProfiles = true
                }
                if didAssignProfiles {
                    needsSnapshotPersistence = true
                }
            } else {
                RuntimeDiagnostics.debug("No profiles available to assign to spaces during load; reconciliation deferred.", category: "TabManager")
            }

            let tabEntities = try context.fetch(FetchDescriptor<TabEntity>())
            let sortedTabs = tabEntities.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                if a.isSpacePinned != b.isSpacePinned { return a.isSpacePinned && !b.isPinned }
                if a.spaceId != b.spaceId {
                    return (a.spaceId?.uuidString ?? "")
                        < (b.spaceId?.uuidString ?? "")
                }
                return a.index < b.index
            }

            let globalPinned = sortedTabs.filter { $0.isPinned }
            let spacePinned = sortedTabs.filter { $0.isSpacePinned && !$0.isPinned }
            let normals = sortedTabs.filter { !$0.isPinned && !$0.isSpacePinned && $0.folderId == nil }

            RuntimeDiagnostics.debug(
                "Loading tabs from store: total=\(sortedTabs.count), pinned=\(globalPinned.count), spacePinned=\(spacePinned.count), regular=\(normals.count)",
                category: "TabManager"
            )

            var pinnedMap: [UUID: [ShortcutPin]] = [:]
            let fallbackProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            var didAssignDefaultProfile = false
            var pendingPins: [ShortcutPin] = []
            for entity in globalPinned {
                let resolvedURL = URL(string: entity.urlString) ?? defaultRestoreURL
                let pin = ShortcutPin(
                    id: entity.id,
                    role: .essential,
                    profileId: entity.profileId ?? fallbackProfileId,
                    spaceId: nil,
                    index: entity.index,
                    folderId: nil,
                    launchURL: resolvedURL,
                    title: entity.name,
                    faviconCacheKey: ShortcutPin.makeFaviconCacheKey(for: resolvedURL),
                    iconAsset: entity.iconAsset
                )
                if let stored = entity.profileId {
                    var pins = pinnedMap[stored] ?? []
                    pins.append(pin)
                    pinnedMap[stored] = pins
                } else if let fallbackProfileId {
                    didAssignDefaultProfile = true
                    var pins = pinnedMap[fallbackProfileId] ?? []
                    pins.append(pin)
                    pinnedMap[fallbackProfileId] = pins
                } else {
                    pendingPins.append(pin)
                }
            }
            pinnedByProfile = pinnedMap
            pendingPinnedWithoutProfile = pendingPins

            for entity in spacePinned {
                if let spaceId = entity.spaceId {
                    let resolvedURL = URL(string: entity.urlString) ?? defaultRestoreURL
                    let pin = ShortcutPin(
                        id: entity.id,
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: spaceId,
                        index: entity.index,
                        folderId: entity.folderId,
                        launchURL: resolvedURL,
                        title: entity.name,
                        faviconCacheKey: ShortcutPin.makeFaviconCacheKey(for: resolvedURL),
                        iconAsset: entity.iconAsset
                    )
                    var pins = spacePinnedShortcuts[spaceId] ?? []
                    pins.append(pin)
                    setSpacePinnedShortcuts(pins, for: spaceId)
                } else {
                    RuntimeDiagnostics.debug("Skipping malformed space-pinned launcher '\(entity.name)' without a spaceId during load.", category: "TabManager")
                }
            }

            for entity in normals {
                let runtimeTab = toRuntime(entity, defaultRestoreURL: defaultRestoreURL)
                if let spaceId = entity.spaceId {
                    var tabs = tabsBySpace[spaceId] ?? []
                    tabs.append(runtimeTab)
                    setTabs(tabs, for: spaceId)
                }
            }

            let folderEntities = try context.fetch(FetchDescriptor<FolderEntity>())
            var didNormalizeFolderIcons = false
            for entity in folderEntities {
                let normalizedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(entity.icon)
                if normalizedIcon != entity.icon {
                    entity.icon = normalizedIcon
                    didNormalizeFolderIcons = true
                }
                let folder = TabFolder(
                    id: entity.id,
                    name: entity.name,
                    spaceId: entity.spaceId,
                    icon: normalizedIcon,
                    color: NSColor(hex: entity.color) ?? .controlAccentColor
                )
                folder.isOpen = entity.isOpen
                var folders = foldersBySpace[entity.spaceId] ?? []
                folders.append(folder)
                setFolders(folders, for: entity.spaceId)
            }

            for tab in allTabsAllSpaces() {
                tab.browserManager = browserManager
            }

            let states = try context.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first
            if spaces.isEmpty {
                let personalSpace = Space(name: "Personal", icon: "person.crop.circle", workspaceTheme: .default)
                spaces.append(personalSpace)
                setTabs([], for: personalSpace.id)
                currentSpace = personalSpace
                needsSnapshotPersistence = true
            } else if let stateSpaceId = state?.currentSpaceID,
                      let match = spaces.first(where: { $0.id == stateSpaceId }) {
                currentSpace = match
            } else {
                currentSpace = spaces.first
            }

            let selectionTabs = currentSpace.flatMap { tabsBySpace[$0.id] } ?? []
            if let selectedTabId = state?.currentTabID,
               let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
                currentTab = match
            } else {
                currentTab = selectionTabs.first
            }

            RuntimeDiagnostics.debug(
                "Current Space: \(currentSpace?.name ?? "None"), Tab: \(currentTab?.name ?? "None")",
                category: "TabManager"
            )
            SidebarUITestDragMarker.recordEvent(
                "startupLoadComplete",
                dragItemID: nil,
                ownerDescription: "TabManager.loadFromStore",
                details: "spaces=\(spaces.count) currentSpace=\(currentSpace?.id.uuidString ?? "nil") currentTab=\(currentTab?.id.uuidString ?? "nil") currentProfile=\(browserManager?.currentProfile?.id.uuidString ?? "nil") pinnedProfiles=\(pinnedByProfile.count) spacePinnedGroups=\(spacePinnedShortcuts.count)"
            )

            if let browserManager, let currentSpace {
                browserManager.syncWorkspaceThemeAcrossWindows(for: currentSpace, animate: false)
            }
            if didAssignDefaultProfile || didNormalizeFolderIcons || didNormalizeSpaceIcons {
                needsSnapshotPersistence = true
            }
            if needsSnapshotPersistence {
                persistSnapshot()
            }
        } catch {
            RuntimeDiagnostics.debug("SwiftData load error: \(String(describing: error))", category: "TabManager")
            SidebarUITestDragMarker.recordEvent(
                "startupLoadFailed",
                dragItemID: nil,
                ownerDescription: "TabManager.loadFromStore",
                details: "error=\(String(describing: error))"
            )
        }
    }

    private func toRuntime(_ entity: TabEntity, defaultRestoreURL: URL) -> Tab {
        let urlString = entity.currentURLString ?? entity.urlString
        let url = URL(string: urlString) ?? URL(string: entity.urlString) ?? defaultRestoreURL
        let faviconName = SumiSurface.isSettingsSurfaceURL(url)
            ? SumiSurface.settingsTabFaviconSystemImageName
            : "globe"
        let tab = Tab(
            id: entity.id,
            url: url,
            name: entity.name,
            favicon: faviconName,
            spaceId: entity.spaceId,
            index: entity.index,
            browserManager: browserManager,
            skipFaviconFetch: true
        )
        tab.folderId = entity.folderId
        tab.isPinned = entity.isPinned
        tab.isSpacePinned = entity.isSpacePinned
        tab.canGoBack = entity.canGoBack
        tab.canGoForward = entity.canGoForward
        return tab
    }
}
