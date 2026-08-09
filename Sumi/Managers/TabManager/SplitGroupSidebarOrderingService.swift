import Foundation
import SumiDomain

@MainActor
final class SplitGroupSidebarOrderingService {
    private let store: SplitGroupStore
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        store: SplitGroupStore,
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.store = store
        self.folders = folders
        self.pins = pins
    }

    var groupsSnapshot: [SplitGroup] { store.groups }

    func group(id: UUID) -> SplitGroup? { store.group(id: id) }

    func resolver(for spaceID: UUID) -> SplitGroupVisualOrderingResolver {
        SplitGroupVisualOrderingResolver(
            spaceID: spaceID,
            splitGroups: store.groups,
            folders: folders.folders(for: spaceID),
            spacePinnedPins: pins.spacePinnedPins(for: spaceID)
        )
    }

    func groups(for spaceID: UUID, folderID: UUID? = nil) -> [SplitGroup] {
        resolver(for: spaceID).shortcutSidebarGroups(inFolder: folderID)
    }

    func topLevelItems(for spaceID: UUID) -> [SplitGroupVisualListItem] {
        resolver(for: spaceID).topLevelItems()
    }

    func favoriteItems(for profileID: UUID?) -> [SplitGroupVisualListItem] {
        guard profileID != nil else { return [] }
        return SidebarVisualOrdering.favoriteItems(
            pins: profileID.map { pins.favoritePins(for: $0) } ?? [],
            groups: store.groups,
            profileID: profileID
        )
    }

    func regularGroups(for spaceID: UUID) -> [SplitGroup] {
        store.groups.filter {
            guard case .regularTabs(let groupSpaceID) = $0.container else {
                return false
            }
            return groupSpaceID == spaceID
        }
    }

    func folderID(for group: SplitGroup, in spaceID: UUID) -> UUID? {
        guard group.container.spaceId == spaceID,
              group.container.isShortcutSidebar else {
            return nil
        }
        return group.container.shortcutSidebarFolderId
    }
}
