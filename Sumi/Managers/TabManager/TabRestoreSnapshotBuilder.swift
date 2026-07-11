import Foundation
import SumiDomain

struct TabRestoreSnapshotBuilder: Sendable {
    func makeSnapshot(
        spaces: [TabRestoreSpaceDTO],
        foldersBySpace: [UUID: [TabPersistenceFolder]],
        tabs: TabRestoreCategorizedTabs,
        splitGroups: [SplitGroup],
        selection: TabPersistenceSelection
    ) -> TabPersistenceSnapshot {
        let snapshotSpaces = spaces.enumerated().map { index, space in
            TabPersistenceSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                workspaceThemeData: space.workspaceTheme.encoded,
                profileId: space.profileId
            )
        }

        var snapshotTabs: [TabPersistenceTab] = []
        for profileId in tabs.pinnedShortcutsByProfile.keys.sorted(by: uuidLessThan) {
            snapshotTabs.append(
                contentsOf: (tabs.pinnedShortcutsByProfile[profileId] ?? []).map(makeTab)
            )
        }
        snapshotTabs.append(contentsOf: tabs.pendingPinnedShortcuts.map(makeTab))

        for space in spaces {
            snapshotTabs.append(
                contentsOf: (tabs.spacePinnedShortcutsBySpace[space.id] ?? []).map(makeTab)
            )
            snapshotTabs.append(
                contentsOf: (tabs.regularTabsBySpace[space.id] ?? []).map { tab in
                    TabPersistenceTab(
                        id: tab.id,
                        urlString: tab.url.absoluteString,
                        name: tab.name,
                        index: tab.index,
                        spaceId: tab.spaceId,
                        isPinned: false,
                        isSpacePinned: false,
                        profileId: tab.profileId,
                        executionProfileId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        currentURLString: tab.url.absoluteString,
                        canGoBack: tab.canGoBack,
                        canGoForward: tab.canGoForward
                    )
                }
            )
        }

        let snapshotFolders = spaces.flatMap { foldersBySpace[$0.id] ?? [] }
        return TabPersistenceSnapshot(
            spaces: snapshotSpaces,
            tabs: snapshotTabs,
            folders: snapshotFolders,
            splitGroups: splitGroups,
            state: selection
        )
    }

    private func makeTab(from shortcut: TabRestoreShortcutDTO) -> TabPersistenceTab {
        TabPersistenceTab(
            id: shortcut.id,
            urlString: shortcut.launchURL.absoluteString,
            name: shortcut.title,
            index: shortcut.index,
            spaceId: shortcut.spaceId,
            isPinned: shortcut.role == .essential,
            isSpacePinned: shortcut.role == .spacePinned,
            profileId: shortcut.profileId,
            executionProfileId: shortcut.executionProfileId,
            folderId: shortcut.folderId,
            iconAsset: shortcut.iconAsset,
            currentURLString: shortcut.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
