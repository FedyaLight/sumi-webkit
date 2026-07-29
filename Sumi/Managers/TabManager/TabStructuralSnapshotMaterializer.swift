import AppKit
import Foundation
import SumiDomain

@MainActor
struct TabStructuralSnapshotMaterializer {
    typealias SnapshotSpace = TabPersistenceSpace
    typealias SnapshotTab = TabPersistenceTab
    typealias SnapshotFolder = TabPersistenceFolder

    func makeSnapshot(
        spaces: [SnapshotSpace],
        tabs: [SnapshotTab],
        folders: [SnapshotFolder],
        splitGroups: [SplitGroup],
        currentTabId: UUID?,
        currentSpaceId: UUID?
    ) -> TabPersistenceSnapshot {
        TabPersistenceSnapshot(
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
    ) -> TabStructuralPersistenceDelta {
        PerformanceTrace.withInterval(
            "TabManager.materializeStructuralDelta"
        ) {
            let tabProjection = makeDirtyTabProjection(
                ids: dirtySet.dirtyTabIds,
                spaces: spaces,
                pinnedByProfile: pinnedByProfile,
                spacePinnedShortcuts: spacePinnedShortcuts,
                tabsBySpace: tabsBySpace,
                shouldPersistRegularTab: shouldPersistRegularTab
            )
            return TabStructuralPersistenceDelta(
                spaces: makeDirtySpaceSnapshots(
                    spaces: spaces,
                    ids: dirtySet.dirtySpaceIds
                ),
                tabs: tabProjection.snapshots,
                folders: makeDirtyFolderSnapshots(
                    ids: dirtySet.dirtyFolderIds,
                    spaces: spaces,
                    foldersBySpace: foldersBySpace
                ),
                splitGroups: dirtySet.splitGroupsDirty
                    ? makeSplitGroupSnapshots(splitGroups) : nil,
                deletedSpaceIds: dirtySet.deletedSpaceIds,
                deletedTabIds: dirtySet.deletedTabIds.union(
                    tabProjection.nonPersistableRegularTabIDs
                ),
                deletedFolderIds: dirtySet.deletedFolderIds,
                state: makeState(
                    currentTabId: currentTabId,
                    currentSpaceId: currentSpaceId
                )
            )
        }
    }

    func makeSpaceSnapshots(spaces: [Space]) -> [TabPersistenceSpace] {
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
    ) -> [TabPersistenceTab] {
        pins.sorted { $0.index < $1.index }.map { pin in
            makePinnedTabSnapshot(pin: pin, profileId: profileId)
        }
    }

    func makeSpacePinnedTabSnapshots(
        spaceId: UUID,
        pins: [ShortcutPin]
    ) -> [TabPersistenceTab] {
        pins.sorted { $0.index < $1.index }.map { pin in
            makeSpacePinnedTabSnapshot(pin: pin, spaceId: spaceId)
        }
    }

    func makeRegularTabSnapshots(
        spaceId: UUID,
        tabs: [Tab],
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> [TabPersistenceTab] {
        tabs.filter(shouldPersistRegularTab).map { tab in
            makeRegularTabSnapshot(tab: tab, spaceId: spaceId)
        }
    }

    func makeFolderSnapshots(
        spaceId: UUID,
        folders: [TabFolder]
    ) -> [TabPersistenceFolder] {
        folders.sorted { $0.index < $1.index }.map { folder in
            makeFolderSnapshot(folder: folder, spaceId: spaceId)
        }
    }

    private func makeState(
        currentTabId: UUID?,
        currentSpaceId: UUID?
    ) -> TabPersistenceSelection {
        TabPersistenceSelection(
            currentTabID: currentTabId,
            currentSpaceID: currentSpaceId
        )
    }

    private func makeDirtySpaceSnapshots(
        spaces: [Space],
        ids: Set<UUID>
    ) -> [TabPersistenceSpace] {
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

    private func makeDirtyTabProjection(
        ids: Set<UUID>,
        spaces: [Space],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        tabsBySpace: [UUID: [Tab]],
        shouldPersistRegularTab: (Tab) -> Bool
    ) -> (
        snapshots: [TabPersistenceTab],
        nonPersistableRegularTabIDs: Set<UUID>
    ) {
        guard ids.isEmpty == false else { return ([], []) }
        var snapshots: [SnapshotTab] = []
        var nonPersistableRegularTabIDs = Set<UUID>()

        for profileId in pinnedByProfile.keys.sorted(by: uuidLessThan) {
            let orderedPins = (pinnedByProfile[profileId] ?? [])
                .filter { ids.contains($0.id) }
                .sorted { $0.index < $1.index }
            for pin in orderedPins {
                snapshots.append(makePinnedTabSnapshot(pin: pin, profileId: profileId))
            }
        }

        for space in spaces {
            let shortcutPins = (spacePinnedShortcuts[space.id] ?? [])
                .filter { ids.contains($0.id) }
                .sorted { $0.index < $1.index }
            for pin in shortcutPins {
                snapshots.append(makeSpacePinnedTabSnapshot(pin: pin, spaceId: space.id))
            }

            for tab in tabsBySpace[space.id] ?? [] where ids.contains(tab.id) {
                if shouldPersistRegularTab(tab) {
                    snapshots.append(
                        makeRegularTabSnapshot(tab: tab, spaceId: space.id)
                    )
                } else {
                    nonPersistableRegularTabIDs.insert(tab.id)
                }
            }
        }

        return (snapshots, nonPersistableRegularTabIDs)
    }

    private func makeDirtyFolderSnapshots(
        ids: Set<UUID>,
        spaces: [Space],
        foldersBySpace: [UUID: [TabFolder]]
    ) -> [TabPersistenceFolder] {
        guard ids.isEmpty == false else { return [] }
        var snapshots: [SnapshotFolder] = []
        for space in spaces {
            let orderedFolders = (foldersBySpace[space.id] ?? [])
                .filter { ids.contains($0.id) }
                .sorted { $0.index < $1.index }
            for folder in orderedFolders {
                snapshots.append(makeFolderSnapshot(folder: folder, spaceId: space.id))
            }
        }
        return snapshots
    }

    private func makePinnedTabSnapshot(
        pin: ShortcutPin,
        profileId: UUID
    ) -> TabPersistenceTab {
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
            titleIsCustom: pin.titleIsCustom,
            currentURLString: pin.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func makeSpacePinnedTabSnapshot(
        pin: ShortcutPin,
        spaceId: UUID
    ) -> TabPersistenceTab {
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
            titleIsCustom: pin.titleIsCustom,
            currentURLString: pin.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func makeRegularTabSnapshot(
        tab: Tab,
        spaceId: UUID
    ) -> TabPersistenceTab {
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
    ) -> TabPersistenceFolder {
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

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
