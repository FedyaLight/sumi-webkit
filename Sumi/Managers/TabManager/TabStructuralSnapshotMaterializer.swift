import AppKit
import Foundation

@MainActor
struct TabStructuralSnapshotMaterializer {
    typealias SnapshotSpace = TabSnapshotRepository.SnapshotSpace
    typealias SnapshotTab = TabSnapshotRepository.SnapshotTab
    typealias SnapshotFolder = TabSnapshotRepository.SnapshotFolder

    func makeSnapshot(
        spaces: [SnapshotSpace],
        tabs: [SnapshotTab],
        folders: [SnapshotFolder],
        splitGroups: [SplitGroup],
        currentTabId: UUID?,
        currentSpaceId: UUID?
    ) -> TabSnapshotRepository.Snapshot {
        TabSnapshotRepository.Snapshot(
            spaces: spaces,
            tabs: tabs,
            folders: folders,
            splitGroups: splitGroups,
            state: makeState(currentTabId: currentTabId, currentSpaceId: currentSpaceId)
        )
    }

    func makeStructuralDelta(
        from dirtySet: TabStructuralDirtySet,
        spaces: [Space],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        tabsBySpace: [UUID: [Tab]],
        foldersBySpace: [UUID: [TabFolder]],
        splitGroups: [SplitGroup],
        currentTabId: UUID?,
        currentSpaceId: UUID?,
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> TabSnapshotRepository.StructuralDelta {
        TabSnapshotRepository.StructuralDelta(
            spaces: makeDirtySpaceSnapshots(spaces: spaces, ids: dirtySet.dirtySpaceIds),
            tabs: makeDirtyTabSnapshots(
                ids: dirtySet.dirtyTabIds,
                spaces: spaces,
                pinnedByProfile: pinnedByProfile,
                spacePinnedShortcuts: spacePinnedShortcuts,
                tabsBySpace: tabsBySpace,
                shouldPersistRegularTab: shouldPersistRegularTab
            ),
            folders: makeDirtyFolderSnapshots(
                ids: dirtySet.dirtyFolderIds,
                spaces: spaces,
                foldersBySpace: foldersBySpace
            ),
            splitGroups: dirtySet.splitGroupsDirty ? makeSplitGroupSnapshots(splitGroups) : nil,
            deletedSpaceIds: dirtySet.deletedSpaceIds,
            deletedTabIds: dirtySet.deletedTabIds
                .union(nonPersistableRegularTabIds(
                    from: dirtySet.dirtyTabIds,
                    tabsBySpace: tabsBySpace,
                    shouldPersistRegularTab: shouldPersistRegularTab
                )),
            deletedFolderIds: dirtySet.deletedFolderIds,
            state: makeState(currentTabId: currentTabId, currentSpaceId: currentSpaceId)
        )
    }

    func makeSpaceSnapshots(spaces: [Space]) -> [TabSnapshotRepository.SnapshotSpace] {
        spaces.enumerated().map { index, space in
            SnapshotSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                workspaceThemeData: space.workspaceTheme.encoded,
                profileId: space.profileId
            )
        }
    }

    func makeSplitGroupSnapshots(_ splitGroups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(splitGroups)
    }

    func makePinnedTabSnapshots(
        profileId: UUID,
        pins: [ShortcutPin]
    ) -> [TabSnapshotRepository.SnapshotTab] {
        pins.sorted { $0.index < $1.index }.map { pin in
            makePinnedTabSnapshot(pin: pin, profileId: profileId)
        }
    }

    func makeSpacePinnedTabSnapshots(
        spaceId: UUID,
        pins: [ShortcutPin]
    ) -> [TabSnapshotRepository.SnapshotTab] {
        pins.sorted { $0.index < $1.index }.map { pin in
            makeSpacePinnedTabSnapshot(pin: pin, spaceId: spaceId)
        }
    }

    func makeRegularTabSnapshots(
        spaceId: UUID,
        tabs: [Tab],
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> [TabSnapshotRepository.SnapshotTab] {
        tabs.filter(shouldPersistRegularTab).map { tab in
            makeRegularTabSnapshot(tab: tab, spaceId: spaceId)
        }
    }

    func makeFolderSnapshots(
        spaceId: UUID,
        folders: [TabFolder]
    ) -> [TabSnapshotRepository.SnapshotFolder] {
        folders.sorted { $0.index < $1.index }.map { folder in
            makeFolderSnapshot(folder: folder, spaceId: spaceId)
        }
    }

    private func makeState(
        currentTabId: UUID?,
        currentSpaceId: UUID?
    ) -> TabSnapshotRepository.SnapshotState {
        TabSnapshotRepository.SnapshotState(
            currentTabID: currentTabId,
            currentSpaceID: currentSpaceId
        )
    }

    private func makeDirtySpaceSnapshots(
        spaces: [Space],
        ids: Set<UUID>
    ) -> [TabSnapshotRepository.SnapshotSpace] {
        guard ids.isEmpty == false else { return [] }
        return spaces.enumerated().compactMap { index, space in
            guard ids.contains(space.id) else { return nil }
            return SnapshotSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                workspaceThemeData: space.workspaceTheme.encoded,
                profileId: space.profileId
            )
        }
    }

    private func makeDirtyTabSnapshots(
        ids: Set<UUID>,
        spaces: [Space],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        tabsBySpace: [UUID: [Tab]],
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> [TabSnapshotRepository.SnapshotTab] {
        guard ids.isEmpty == false else { return [] }
        var snapshots: [SnapshotTab] = []

        for profileId in pinnedByProfile.keys.sorted(by: uuidLessThan) {
            let orderedPins = Array(pinnedByProfile[profileId] ?? []).sorted { $0.index < $1.index }
            for pin in orderedPins where ids.contains(pin.id) {
                snapshots.append(makePinnedTabSnapshot(pin: pin, profileId: profileId))
            }
        }

        for space in spaces {
            let shortcutPins = Array(spacePinnedShortcuts[space.id] ?? []).sorted { $0.index < $1.index }
            for pin in shortcutPins where ids.contains(pin.id) {
                snapshots.append(makeSpacePinnedTabSnapshot(pin: pin, spaceId: space.id))
            }

            let regularTabs = Array(tabsBySpace[space.id] ?? [])
            for tab in regularTabs where ids.contains(tab.id) && shouldPersistRegularTab(tab) {
                snapshots.append(makeRegularTabSnapshot(tab: tab, spaceId: space.id))
            }
        }

        return snapshots
    }

    private func makeDirtyFolderSnapshots(
        ids: Set<UUID>,
        spaces: [Space],
        foldersBySpace: [UUID: [TabFolder]]
    ) -> [TabSnapshotRepository.SnapshotFolder] {
        guard ids.isEmpty == false else { return [] }
        var snapshots: [SnapshotFolder] = []
        for space in spaces {
            let orderedFolders = (foldersBySpace[space.id] ?? []).sorted { $0.index < $1.index }
            for folder in orderedFolders where ids.contains(folder.id) {
                snapshots.append(makeFolderSnapshot(folder: folder, spaceId: space.id))
            }
        }
        return snapshots
    }

    private func makePinnedTabSnapshot(
        pin: ShortcutPin,
        profileId: UUID
    ) -> TabSnapshotRepository.SnapshotTab {
        SnapshotTab(
            id: pin.id,
            urlString: pin.launchURL.absoluteString,
            name: pin.title,
            index: pin.index,
            spaceId: nil,
            isPinned: true,
            isSpacePinned: false,
            profileId: profileId,
            executionProfileId: pin.executionProfileId,
            folderId: nil,
            iconAsset: pin.iconAsset,
            currentURLString: pin.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func makeSpacePinnedTabSnapshot(
        pin: ShortcutPin,
        spaceId: UUID
    ) -> TabSnapshotRepository.SnapshotTab {
        SnapshotTab(
            id: pin.id,
            urlString: pin.launchURL.absoluteString,
            name: pin.title,
            index: pin.index,
            spaceId: spaceId,
            isPinned: false,
            isSpacePinned: true,
            profileId: nil,
            executionProfileId: pin.executionProfileId,
            folderId: pin.folderId,
            iconAsset: pin.iconAsset,
            currentURLString: pin.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func makeRegularTabSnapshot(
        tab: Tab,
        spaceId: UUID
    ) -> TabSnapshotRepository.SnapshotTab {
        SnapshotTab(
            id: tab.id,
            urlString: tab.url.absoluteString,
            name: tab.name,
            index: tab.index,
            spaceId: spaceId,
            isPinned: false,
            isSpacePinned: false,
            profileId: tab.profileId,
            executionProfileId: nil,
            folderId: tab.folderId,
            iconAsset: nil,
            currentURLString: tab.url.absoluteString,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }

    private func makeFolderSnapshot(
        folder: TabFolder,
        spaceId: UUID
    ) -> TabSnapshotRepository.SnapshotFolder {
        SnapshotFolder(
            id: folder.id,
            name: folder.name,
            icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon),
            color: folder.color.toHexString() ?? "#000000",
            spaceId: spaceId,
            parentFolderId: folder.parentFolderId,
            isOpen: folder.isOpen,
            index: folder.index
        )
    }

    private func nonPersistableRegularTabIds(
        from ids: Set<UUID>,
        tabsBySpace: [UUID: [Tab]],
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> Set<UUID> {
        guard ids.isEmpty == false else { return [] }

        var deletedIds = Set<UUID>()
        for tabs in tabsBySpace.values {
            for tab in tabs where ids.contains(tab.id) && shouldPersistRegularTab(tab) == false {
                deletedIds.insert(tab.id)
            }
        }
        return deletedIds
    }

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
