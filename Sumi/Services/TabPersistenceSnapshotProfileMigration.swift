import Foundation
import SumiDomain

@MainActor
enum TabPersistenceSnapshotProfileMigration {
    static func migrate(
        _ snapshot: TabPersistenceSnapshot,
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> TabPersistenceSnapshot? {
        let migratedSpaces = snapshot.spaces.map { space in
            TabPersistenceSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: space.index,
                workspaceThemeData: space.workspaceThemeData,
                profileId: replacement(
                    for: space.profileId,
                    from: deletedProfileID,
                    to: fallbackProfileID
                )
            )
        }
        let migratedTabs = snapshot.tabs.map { tab in
            TabPersistenceTab(
                id: tab.id,
                urlString: tab.urlString,
                name: tab.name,
                index: tab.index,
                spaceId: tab.spaceId,
                isPinned: tab.isPinned,
                isSpacePinned: tab.isSpacePinned,
                profileId: replacement(
                    for: tab.profileId,
                    from: deletedProfileID,
                    to: fallbackProfileID
                ),
                executionProfileId: replacement(
                    for: tab.executionProfileId,
                    from: deletedProfileID,
                    to: fallbackProfileID
                ),
                folderId: tab.folderId,
                iconAsset: tab.iconAsset,
                currentURLString: tab.currentURLString,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
        }
        let migratedGroups = snapshot.splitGroups.compactMap {
            migrate(
                $0,
                from: deletedProfileID,
                to: fallbackProfileID
            )
        }
        guard migratedGroups.count == snapshot.splitGroups.count else {
            return nil
        }

        let migrated = TabPersistenceSnapshot(
            spaces: migratedSpaces,
            tabs: migratedTabs,
            folders: snapshot.folders,
            splitGroups: migratedGroups,
            state: snapshot.state
        )
        guard ProfileReferenceInventory(tabSnapshot: migrated)
            .contains(deletedProfileID) == false else {
            return nil
        }
        return migrated
    }

    private static func migrate(
        _ group: SplitGroup,
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> SplitGroup? {
        let migratedContainer: SplitGroupContainer
        switch group.container {
        case .regularTabs:
            migratedContainer = group.container
        case .shortcutSidebar(
            let spaceID,
            let profileID,
            let folderID,
            let index
        ):
            migratedContainer = .shortcutSidebar(
                spaceId: spaceID,
                profileId: replacement(
                    for: profileID,
                    from: deletedProfileID,
                    to: fallbackProfileID
                ),
                folderId: folderID,
                index: index
            )
        }
        guard var migrated = group.changingContainer(
            to: migratedContainer
        ) else {
            return nil
        }

        for member in group.members {
            guard case .essential(let profileID, let index) = member.returnPlacement,
                  profileID == deletedProfileID,
                  case .shortcutPin(let pinID) = member.memberID else {
                continue
            }
            let replacement = SplitMember.shortcutPin(
                pinID,
                returnPlacement: .essential(
                    profileId: fallbackProfileID,
                    index: index
                )
            )
            guard let next = migrated.replacingMember(
                member.memberID,
                with: replacement
            ) else {
                return nil
            }
            migrated = next
        }
        return migrated
    }

    private static func replacement(
        for profileID: UUID?,
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> UUID? {
        profileID == deletedProfileID ? fallbackProfileID : profileID
    }
}
