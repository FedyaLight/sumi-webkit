import AppKit
import Foundation

/// Owns last-session restore: resetting live regular tabs and shortcut live
/// instances at startup, and merging a persisted snapshot back into the live
/// space/folder/pin/tab collections.
@MainActor
final class TabLastSessionRestoreOwner {
    struct Dependencies {
        let requireRuntimePorts: @MainActor () -> RuntimePortRegistry
        let withStructuralUpdateTransactionVoid: @MainActor (@MainActor () -> Void) -> Void
        let lazyRestoreCoordinator: TabLazyRestoreCoordinator
        let transientTabRegistryOwner: TabTransientTabRegistryOwner
        let cancelRuntimeStatePersistence: @MainActor (UUID) -> Void
        let tabCollectionMembershipOwner: TabCollectionMembershipOwner
        let notifyTransientShortcutStateChanged: @MainActor () -> Void
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let regularTabCollectionOwner: RegularTabCollectionOwner
        let regularTabCollectionStateOwner: RegularTabCollectionStateOwner
        let structuralCollectionMutationOwner: TabStructuralCollectionMutationOwner
        let markSpacesSnapshotDirty: @MainActor () -> Void
        let selectionStateOwner: TabSelectionStateOwner
        let scheduleStructuralPersistence: @MainActor () -> Void
        let objectWillChange: @MainActor () -> Void
        let markAllSpacesStructurallyDirty: @MainActor () -> Void
        let folderCollectionStateOwner: TabFolderCollectionStateOwner
        let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
        let shortcutPinStoreOwner: ShortcutPinStoreOwner
        let spacePinnedStructureOwner: SpacePinnedStructureOwner
        let faviconService: any BrowserFaviconServicing
        let faviconImageService: any BrowserFaviconImageServicing
        let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func resetRegularTabsAndShortcutLiveInstancesForStartup() {
        let runtimePorts = dependencies.requireRuntimePorts()
        dependencies.withStructuralUpdateTransactionVoid {
            dependencies.lazyRestoreCoordinator.clear()
            let liveShortcutTabs = dependencies.transientTabRegistryOwner.transientShortcutTabs
            if !liveShortcutTabs.isEmpty {
                for tab in liveShortcutTabs {
                    dependencies.cancelRuntimeStatePersistence(tab.id)
                    tab.performComprehensiveWebViewCleanup()
                    runtimePorts.webViewLifecycle.unloadTab(tab)
                    runtimePorts.webViewLifecycle.requireRemoveAllWebViews(
                        for: tab,
                        closeActiveFullscreenMedia: true
                    )
                    dependencies.tabCollectionMembershipOwner.detach(tab)
                }
                dependencies.transientTabRegistryOwner.replaceTransientShortcutTabsByWindow([:])
                dependencies.notifyTransientShortcutStateChanged()
            }

            for space in dependencies.spaceStateOwner.spaces {
                let regularTabs = dependencies.regularTabCollectionOwner.tabs(in: space)
                for tab in regularTabs {
                    dependencies.cancelRuntimeStatePersistence(tab.id)
                    runtimePorts.webViewLifecycle.unloadTab(tab)
                    runtimePorts.webViewLifecycle.requireRemoveAllWebViews(
                        for: tab,
                        closeActiveFullscreenMedia: true
                    )
                    dependencies.tabCollectionMembershipOwner.detach(tab)
                }
                dependencies.structuralCollectionMutationOwner.setTabs([], for: space.id)
                if space.activeTabId != nil {
                    space.activeTabId = nil
                    dependencies.markSpacesSnapshotDirty()
                }
            }

            dependencies.selectionStateOwner.replaceCurrentTab(nil)
            dependencies.scheduleStructuralPersistence()
        }
    }

    func mergeSnapshotForLastSessionRestore(_ snapshot: TabSnapshotRepository.Snapshot) {
        dependencies.withStructuralUpdateTransactionVoid {
            mergeSpaces(from: snapshot.spaces)
            mergeFolders(from: snapshot.folders)
            mergeShortcutPins(from: snapshot.tabs.filter { $0.isPinned })
            mergeSpacePinnedShortcuts(from: snapshot.tabs.filter { !$0.isPinned && $0.isSpacePinned })
            mergeRegularTabs(from: snapshot.tabs.filter { !$0.isPinned && !$0.isSpacePinned })

            if let currentSpaceId = snapshot.state.currentSpaceID,
               let restoredSpace = dependencies.spaceStateOwner.space(with: currentSpaceId) {
                dependencies.spaceStateOwner.replaceCurrentSpace(restoredSpace)
            } else if dependencies.spaceStateOwner.currentSpace == nil {
                dependencies.spaceStateOwner.replaceCurrentSpace(dependencies.spaceStateOwner.firstSpace)
            }

            if let currentTabId = snapshot.state.currentTabID,
               let restoredTab = dependencies.tabCollectionMembershipOwner.tab(for: currentTabId) {
                dependencies.selectionStateOwner.replaceCurrentTab(restoredTab)
            }

            dependencies.lazyRestoreCoordinator.reset(
                restoredTabIDs: Set(
                    snapshot.tabs
                        .filter { !$0.isPinned && !$0.isSpacePinned }
                        .map(\.id)
                )
            )
            dependencies.scheduleStructuralPersistence()
        }
    }

    private func mergeSpaces(from snapshotSpaces: [TabSnapshotRepository.SnapshotSpace]) {
        var didAddSpace = false
        for snapshotSpace in snapshotSpaces.sorted(by: sortSnapshotSpaces) {
            let restoredTheme = restoredWorkspaceTheme(from: snapshotSpace)
            if let existing = dependencies.spaceStateOwner.space(with: snapshotSpace.id) {
                existing.name = snapshotSpace.name
                existing.icon = SumiPersistentGlyph.normalizedSpaceIconValue(snapshotSpace.icon)
                existing.workspaceTheme = restoredTheme
                existing.profileId = snapshotSpace.profileId
                continue
            }

            dependencies.objectWillChange()
            dependencies.spaceStateOwner.append(
                Space(
                    id: snapshotSpace.id,
                    name: snapshotSpace.name,
                    icon: snapshotSpace.icon,
                    workspaceTheme: restoredTheme,
                    profileId: snapshotSpace.profileId
                )
            )
            didAddSpace = true
        }

        let order = Dictionary(uniqueKeysWithValues: snapshotSpaces.map { ($0.id, $0.index) })
        dependencies.objectWillChange()
        dependencies.spaceStateOwner.sort {
            let lhs = order[$0.id] ?? Int.max
            let rhs = order[$1.id] ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.id.uuidString < $1.id.uuidString
        }

        if didAddSpace {
            for space in dependencies.spaceStateOwner.spaces
            where dependencies.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id] == nil {
                dependencies.structuralCollectionMutationOwner.setTabs([], for: space.id)
            }
        }
        dependencies.markAllSpacesStructurallyDirty()
    }

    private func mergeFolders(from snapshotFolders: [TabSnapshotRepository.SnapshotFolder]) {
        let foldersBySnapshotSpace = Dictionary(grouping: snapshotFolders, by: \.spaceId)
        for (spaceId, snapshotFolders) in foldersBySnapshotSpace {
            guard dependencies.spaceStateOwner.contains(spaceId: spaceId) else { continue }
            var existingFolders = dependencies.folderCollectionStateOwner.folders(for: spaceId)
            for snapshotFolder in snapshotFolders.sorted(by: sortSnapshotFolders) {
                if let index = existingFolders.firstIndex(where: { $0.id == snapshotFolder.id }) {
                    existingFolders[index].name = snapshotFolder.name
                    existingFolders[index].icon = snapshotFolder.icon
                    existingFolders[index].color = NSColor(hex: snapshotFolder.color) ?? .controlAccentColor
                    existingFolders[index].parentFolderId = snapshotFolder.parentFolderId
                    existingFolders[index].isOpen = snapshotFolder.isOpen
                    existingFolders[index].index = snapshotFolder.index
                } else {
                    let folder = TabFolder(
                        id: snapshotFolder.id,
                        name: snapshotFolder.name,
                        spaceId: snapshotFolder.spaceId,
                        parentFolderId: snapshotFolder.parentFolderId,
                        icon: snapshotFolder.icon,
                        color: NSColor(hex: snapshotFolder.color) ?? .controlAccentColor,
                        index: snapshotFolder.index
                    )
                    folder.isOpen = snapshotFolder.isOpen
                    existingFolders.append(folder)
                }
            }
            existingFolders.sort(by: sortFolders)
            dependencies.structuralCollectionMutationOwner.setFolders(existingFolders, for: spaceId)
        }
    }

    private func mergeShortcutPins(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let pinsByProfile = Dictionary(grouping: snapshotTabs, by: \.profileId)
        for (profileId, snapshotTabs) in pinsByProfile {
            guard let profileId else { continue }
            var pins = dependencies.shortcutPinCollectionStateOwner.essentialPins(for: profileId)
            for snapshotTab in snapshotTabs.sorted(by: sortSnapshotTabs) {
                guard pins.contains(where: { $0.id == snapshotTab.id }) == false,
                      let url = URL(string: snapshotTab.urlString)
                else {
                    continue
                }
                pins.append(
                    ShortcutPin(
                        id: snapshotTab.id,
                        role: .essential,
                        profileId: profileId,
                        executionProfileId: snapshotTab.executionProfileId,
                        index: snapshotTab.index,
                        launchURL: url,
                        title: snapshotTab.name,
                        iconAsset: snapshotTab.iconAsset
                    )
                )
            }
            dependencies.structuralCollectionMutationOwner.setPinnedTabs(
                dependencies.shortcutPinStoreOwner.reindexed(pins.sorted(by: sortPins)),
                for: profileId
            )
        }
    }

    private func mergeSpacePinnedShortcuts(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let pinsBySpace = Dictionary(grouping: snapshotTabs.compactMap { snapshotTab -> (UUID, TabSnapshotRepository.SnapshotTab)? in
            guard let spaceId = snapshotTab.spaceId else { return nil }
            return (spaceId, snapshotTab)
        }, by: \.0)

        for (spaceId, entries) in pinsBySpace {
            guard dependencies.spaceStateOwner.contains(spaceId: spaceId) else { continue }
            var pins = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
            for snapshotTab in entries.map(\.1).sorted(by: sortSnapshotTabs) {
                guard pins.contains(where: { $0.id == snapshotTab.id }) == false,
                      let url = URL(string: snapshotTab.urlString)
                else {
                    continue
                }
                pins.append(
                    ShortcutPin(
                        id: snapshotTab.id,
                        role: .spacePinned,
                        executionProfileId: snapshotTab.executionProfileId ?? snapshotTab.profileId,
                        spaceId: spaceId,
                        index: snapshotTab.index,
                        folderId: snapshotTab.folderId,
                        launchURL: url,
                        title: snapshotTab.name,
                        iconAsset: snapshotTab.iconAsset
                    )
                )
            }
            dependencies.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
                dependencies.spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(pins),
                for: spaceId
            )
        }
    }

    private func mergeRegularTabs(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let tabsBySnapshotSpace = Dictionary(grouping: snapshotTabs.compactMap { snapshotTab -> (UUID, TabSnapshotRepository.SnapshotTab)? in
            guard let spaceId = snapshotTab.spaceId else { return nil }
            return (spaceId, snapshotTab)
        }, by: \.0)

        for (spaceId, entries) in tabsBySnapshotSpace {
            guard dependencies.spaceStateOwner.contains(spaceId: spaceId) else { continue }
            var tabs = dependencies.regularTabCollectionOwner.tabs(in: spaceId)
            for snapshotTab in entries.map(\.1).sorted(by: sortSnapshotTabs) {
                guard tabs.contains(where: { $0.id == snapshotTab.id }) == false,
                      let url = URL(string: snapshotTab.currentURLString ?? snapshotTab.urlString)
                        ?? URL(string: snapshotTab.urlString)
                else {
                    continue
                }

                let tab = Tab(
                    id: snapshotTab.id,
                    url: url,
                    name: snapshotTab.name,
                    favicon: "globe",
                    spaceId: spaceId,
                    index: snapshotTab.index,
                    loadsCachedFaviconOnInit: false,
                    faviconService: dependencies.faviconService,
                    faviconImageService: dependencies.faviconImageService,
                    visitedLinkStore: dependencies.visitedLinkStore
                )
                tab.canGoBack = snapshotTab.canGoBack
                tab.canGoForward = snapshotTab.canGoForward
                tab.profileId = snapshotTab.profileId
                    ?? dependencies.spaceStateOwner.profileId(for: spaceId)
                dependencies.tabCollectionMembershipOwner.attach(tab)
                tabs.append(tab)
            }
            tabs.sort(by: sortTabs)
            dependencies.structuralCollectionMutationOwner.setTabs(tabs, for: spaceId)
        }
    }

    private func sortSnapshotSpaces(
        _ lhs: TabSnapshotRepository.SnapshotSpace,
        _ rhs: TabSnapshotRepository.SnapshotSpace
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortSnapshotFolders(
        _ lhs: TabSnapshotRepository.SnapshotFolder,
        _ rhs: TabSnapshotRepository.SnapshotFolder
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortSnapshotTabs(
        _ lhs: TabSnapshotRepository.SnapshotTab,
        _ rhs: TabSnapshotRepository.SnapshotTab
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortFolders(_ lhs: TabFolder, _ rhs: TabFolder) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortPins(_ lhs: ShortcutPin, _ rhs: ShortcutPin) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortTabs(_ lhs: Tab, _ rhs: Tab) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func restoredWorkspaceTheme(
        from snapshotSpace: TabSnapshotRepository.SnapshotSpace
    ) -> WorkspaceTheme {
        if let data = snapshotSpace.workspaceThemeData,
           let theme = WorkspaceTheme.decode(data) {
            return theme
        }
        return .default
    }
}

extension TabLastSessionRestoreOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            requireRuntimePorts: { [weak tabManager] in
                guard let tabManager else {
                    preconditionFailure("TabManager dependency used after deallocation")
                }
                return tabManager.requireRuntimePorts()
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.withStructuralUpdateTransaction(operation)
            },
            lazyRestoreCoordinator: tabManager.lazyRestoreCoordinator,
            transientTabRegistryOwner: tabManager.transientTabRegistryOwner,
            cancelRuntimeStatePersistence: { [weak tabManager] tabId in
                tabManager?.structuralPersistence.cancelRuntimeStatePersistence(for: tabId)
            },
            tabCollectionMembershipOwner: tabManager.tabCollectionMembershipOwner,
            notifyTransientShortcutStateChanged: { [weak tabManager] in
                tabManager?.notifyTransientShortcutStateChanged()
            },
            spaceStateOwner: tabManager.spaceStateOwner,
            regularTabCollectionOwner: tabManager.regularTabCollectionOwner,
            regularTabCollectionStateOwner: tabManager.regularTabCollectionStateOwner,
            structuralCollectionMutationOwner: tabManager.structuralCollectionMutationOwner,
            markSpacesSnapshotDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markSpacesSnapshotDirty()
            },
            selectionStateOwner: tabManager.selectionStateOwner,
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            objectWillChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            markAllSpacesStructurallyDirty: { [weak tabManager] in
                tabManager?.structuralPersistence.markAllSpacesStructurallyDirty()
            },
            folderCollectionStateOwner: tabManager.folderCollectionStateOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            shortcutPinStoreOwner: tabManager.shortcutPinStoreOwner,
            spacePinnedStructureOwner: tabManager.spacePinnedStructureOwner,
            faviconService: tabManager.faviconService,
            faviconImageService: tabManager.faviconImageService,
            visitedLinkStore: tabManager.visitedLinkStore
        )
    }
}
