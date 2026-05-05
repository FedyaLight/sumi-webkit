//
//  TabManager+StartupRestore.swift
//  Sumi
//

import AppKit
import Foundation

@MainActor
extension TabManager {
    func resetRegularTabsAndShortcutLiveInstancesForStartup() {
        withStructuralUpdateTransaction {
            let liveShortcutTabs = transientShortcutTabsByWindow.values.flatMap(\.values)
            if !liveShortcutTabs.isEmpty {
                for tab in liveShortcutTabs {
                    cancelRuntimeStatePersistence(for: tab.id)
                    tab.performComprehensiveWebViewCleanup()
                    browserManager?.compositorManager.unloadTab(tab)
                    browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)
                    detach(tab)
                }
                transientShortcutTabsByWindow.removeAll()
                notifyTransientShortcutStateChanged()
            }

            for space in spaces {
                let regularTabs = tabsBySpace[space.id] ?? []
                for tab in regularTabs {
                    cancelRuntimeStatePersistence(for: tab.id)
                    browserManager?.compositorManager.unloadTab(tab)
                    browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)
                    detach(tab)
                }
                setTabs([], for: space.id)
                if space.activeTabId != nil {
                    space.activeTabId = nil
                    markSpacesSnapshotDirty()
                }
            }

            currentTab = nil
            scheduleStructuralPersistence()
        }
    }

    func mergeSnapshotForLastSessionRestore(_ snapshot: TabSnapshotRepository.Snapshot) {
        withStructuralUpdateTransaction {
            mergeSpaces(from: snapshot.spaces)
            mergeFolders(from: snapshot.folders)
            mergeShortcutPins(from: snapshot.tabs.filter { $0.isPinned })
            mergeSpacePinnedShortcuts(from: snapshot.tabs.filter { !$0.isPinned && $0.isSpacePinned })
            mergeRegularTabs(from: snapshot.tabs.filter { !$0.isPinned && !$0.isSpacePinned })

            if let currentSpaceId = snapshot.state.currentSpaceID,
               let restoredSpace = spaces.first(where: { $0.id == currentSpaceId }) {
                currentSpace = restoredSpace
            } else if currentSpace == nil {
                currentSpace = spaces.first
            }

            if let currentTabId = snapshot.state.currentTabID,
               let restoredTab = tab(for: currentTabId) {
                currentTab = restoredTab
            }

            scheduleStructuralPersistence()
        }
    }

    private func mergeSpaces(from snapshotSpaces: [TabSnapshotRepository.SnapshotSpace]) {
        var didAddSpace = false
        for snapshotSpace in snapshotSpaces.sorted(by: sortSnapshotSpaces) {
            let restoredTheme = restoredWorkspaceTheme(from: snapshotSpace)
            if let existing = spaces.first(where: { $0.id == snapshotSpace.id }) {
                existing.name = snapshotSpace.name
                existing.icon = SumiPersistentGlyph.normalizedSpaceIconValue(snapshotSpace.icon)
                existing.workspaceTheme = restoredTheme
                existing.profileId = snapshotSpace.profileId
                continue
            }

            spaces.append(
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
        spaces.sort {
            let lhs = order[$0.id] ?? Int.max
            let rhs = order[$1.id] ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.id.uuidString < $1.id.uuidString
        }

        if didAddSpace {
            for space in spaces where tabsBySpace[space.id] == nil {
                setTabs([], for: space.id)
            }
        }
        markAllSpacesStructurallyDirty()
    }

    private func mergeFolders(from snapshotFolders: [TabSnapshotRepository.SnapshotFolder]) {
        let foldersBySnapshotSpace = Dictionary(grouping: snapshotFolders, by: \.spaceId)
        for (spaceId, snapshotFolders) in foldersBySnapshotSpace {
            guard spaces.contains(where: { $0.id == spaceId }) else { continue }
            var existingFolders = foldersBySpace[spaceId] ?? []
            for snapshotFolder in snapshotFolders.sorted(by: sortSnapshotFolders) {
                if let index = existingFolders.firstIndex(where: { $0.id == snapshotFolder.id }) {
                    existingFolders[index].name = snapshotFolder.name
                    existingFolders[index].icon = snapshotFolder.icon
                    existingFolders[index].color = NSColor(hex: snapshotFolder.color) ?? .controlAccentColor
                    existingFolders[index].isOpen = snapshotFolder.isOpen
                    existingFolders[index].index = snapshotFolder.index
                } else {
                    let folder = TabFolder(
                        id: snapshotFolder.id,
                        name: snapshotFolder.name,
                        spaceId: snapshotFolder.spaceId,
                        icon: snapshotFolder.icon,
                        color: NSColor(hex: snapshotFolder.color) ?? .controlAccentColor,
                        index: snapshotFolder.index
                    )
                    folder.isOpen = snapshotFolder.isOpen
                    existingFolders.append(folder)
                }
            }
            existingFolders.sort(by: sortFolders)
            setFolders(existingFolders, for: spaceId)
        }
    }

    private func mergeShortcutPins(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let pinsByProfile = Dictionary(grouping: snapshotTabs, by: \.profileId)
        for (profileId, snapshotTabs) in pinsByProfile {
            guard let profileId else { continue }
            var pins = pinnedByProfile[profileId] ?? []
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
                        index: snapshotTab.index,
                        launchURL: url,
                        title: snapshotTab.name,
                        iconAsset: snapshotTab.iconAsset
                    )
                )
            }
            setPinnedTabs(reindexed(pins.sorted(by: sortPins)), for: profileId)
        }
    }

    private func mergeSpacePinnedShortcuts(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let pinsBySpace = Dictionary(grouping: snapshotTabs.compactMap { snapshotTab -> (UUID, TabSnapshotRepository.SnapshotTab)? in
            guard let spaceId = snapshotTab.spaceId else { return nil }
            return (spaceId, snapshotTab)
        }, by: \.0)

        for (spaceId, entries) in pinsBySpace {
            guard spaces.contains(where: { $0.id == spaceId }) else { continue }
            var pins = spacePinnedShortcuts[spaceId] ?? []
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
                        spaceId: spaceId,
                        index: snapshotTab.index,
                        folderId: snapshotTab.folderId,
                        launchURL: url,
                        title: snapshotTab.name,
                        iconAsset: snapshotTab.iconAsset
                    )
                )
            }
            setSpacePinnedShortcuts(normalizedSpacePinnedShortcuts(pins), for: spaceId)
        }
    }

    private func mergeRegularTabs(from snapshotTabs: [TabSnapshotRepository.SnapshotTab]) {
        let tabsBySnapshotSpace = Dictionary(grouping: snapshotTabs.compactMap { snapshotTab -> (UUID, TabSnapshotRepository.SnapshotTab)? in
            guard let spaceId = snapshotTab.spaceId else { return nil }
            return (spaceId, snapshotTab)
        }, by: \.0)

        for (spaceId, entries) in tabsBySnapshotSpace {
            guard spaces.contains(where: { $0.id == spaceId }) else { continue }
            var tabs = tabsBySpace[spaceId] ?? []
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
                    browserManager: browserManager
                )
                tab.canGoBack = snapshotTab.canGoBack
                tab.canGoForward = snapshotTab.canGoForward
                tab.profileId = spaces.first(where: { $0.id == spaceId })?.profileId
                _ = tab.applyCachedFaviconOrPlaceholder(for: url)
                attach(tab)
                tabs.append(tab)
            }
            tabs.sort(by: sortTabs)
            setTabs(tabs, for: spaceId)
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
           let theme = WorkspaceTheme.decode(data)
        {
            return theme
        }
        if let data = snapshotSpace.gradientData {
            return WorkspaceTheme(gradient: SpaceGradient.decode(data))
        }
        return .default
    }
}
