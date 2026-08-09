import Foundation

@MainActor
final class TabLastSessionLiveStateSnapshotter {
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let shortcutPins: ShortcutPinCollectionStateOwner
    private let regularTabs: RegularTabCollectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        shortcutPins: ShortcutPinCollectionStateOwner,
        regularTabs: RegularTabCollectionStateOwner
    ) {
        self.spaces = spaces
        self.folders = folders
        self.shortcutPins = shortcutPins
        self.regularTabs = regularTabs
    }

    func prepare() -> (
        live: TabLastSessionLiveState,
        spaces: [UUID: Space],
        folders: [TabLastSessionFolderKey: TabFolder],
        tabs: [TabLastSessionRegularTabKey: Tab]
    ) {
        let orderedSpaces = spaces.spaces
        let foldersBySpace = folders.foldersBySpaceSnapshot().mapValues {
            $0.map {
                TabLastSessionLiveState.FolderReference(
                    id: $0.id,
                    spaceId: $0.spaceId,
                    parentFolderId: $0.parentFolderId,
                    index: $0.index
                )
            }
        }
        let favoritePins = shortcutPins.pinnedByProfileSnapshot().mapValues {
            $0.map(shortcutDescriptor)
        }
        let spacePins = shortcutPins.spacePinnedShortcutsSnapshot().mapValues {
            $0.map(shortcutDescriptor)
        }
        let regularTabsBySpace = regularTabs.tabsBySpaceSnapshot()
        let live = TabLastSessionLiveState(
            spaces: orderedSpaces.map { .init(id: $0.id, profileId: $0.profileId) },
            currentSpaceId: spaces.currentSpaceId,
            foldersBySpace: foldersBySpace,
            favoritePinsByProfile: favoritePins,
            spacePinnedShortcuts: spacePins,
            regularTabsBySpace: regularTabsBySpace.mapValues {
                $0.map {
                    TabLastSessionLiveState.RegularTabReference(
                        id: $0.id,
                        index: $0.index
                    )
                }
            }
        )
        let folderInventory = folders.foldersBySpaceSnapshot().reduce(
            into: [TabLastSessionFolderKey: TabFolder]()
        ) {
            result, entry in
            for folder in entry.value {
                result[TabLastSessionFolderKey(
                    spaceID: entry.key,
                    folderID: folder.id
                )] = folder
            }
        }
        let tabInventory = regularTabsBySpace.reduce(
            into: [TabLastSessionRegularTabKey: Tab]()
        ) {
            result, entry in
            for tab in entry.value {
                result[TabLastSessionRegularTabKey(
                    spaceID: entry.key,
                    tabID: tab.id
                )] = tab
            }
        }
        return (
            live,
            Dictionary(uniqueKeysWithValues: orderedSpaces.map { ($0.id, $0) }),
            folderInventory,
            tabInventory
        )
    }

    private func shortcutDescriptor(
        _ pin: ShortcutPin
    ) -> TabLastSessionShortcutDescriptor {
        TabLastSessionShortcutDescriptor(
            id: pin.id,
            kind: pin.role == .favorite ? .favorite : .spacePinned,
            profileId: pin.profileId,
            executionProfileId: pin.executionProfileId,
            spaceId: pin.spaceId,
            index: pin.index,
            folderId: pin.folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            iconAsset: pin.iconAsset,
            titleIsCustom: pin.titleIsCustom
        )
    }
}
