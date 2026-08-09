import Foundation
import SumiDomain

@MainActor
final class SidebarSplitGroupMoveService {
    enum Destination {
        case regular(spaceID: UUID)
        case pinned(spaceID: UUID)
        case favorite(profileID: UUID)
        case folder(id: UUID, name: String, spaceID: UUID)
    }

    private let ordering: SplitGroupSidebarOrderingService
    private let conversion: SplitGroupContainerConversion
    private let folders: TabFolderCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner

    init(
        ordering: SplitGroupSidebarOrderingService,
        conversion: SplitGroupContainerConversion,
        folders: TabFolderCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner
    ) {
        self.ordering = ordering
        self.conversion = conversion
        self.folders = folders
        self.regularTabs = regularTabs
    }

    func destinations(
        for group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> [Destination] {
        guard let group = ordering.group(id: group.id),
              let spaceID = group.container.spaceId
                ?? windowState.currentSpaceId else { return [] }
        var result: [Destination] = []
        if group.container != .regularTabs(spaceId: spaceID) {
            result.append(.regular(spaceID: spaceID))
        }
        if !(group.container.isShortcutSidebar
            && group.container.spaceId == spaceID
            && group.container.shortcutSidebarFolderId == nil) {
            result.append(.pinned(spaceID: spaceID))
        }
        if let profileID = windowState.currentProfileId,
           !isFavorite(group, profileID: profileID),
           ordering.favoriteItems(for: profileID).count
                < FavoriteShortcutPlacementOwner.CapacityPolicy.maxItems {
            result.append(.favorite(profileID: profileID))
        }
        result.append(contentsOf: folders.folders(for: spaceID).compactMap {
            folder in
            guard !folder.isLiveFolder,
                  group.container.shortcutSidebarFolderId != folder.id else {
                return nil
            }
            return .folder(
                id: folder.id,
                name: folder.name,
                spaceID: spaceID
            )
        })
        return result
    }

    func move(
        _ group: SplitGroup,
        to destination: Destination,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let canonicalGroup = ordering.group(id: group.id),
              let source = source(for: canonicalGroup),
              let scope = SidebarDragScope(
                  windowState: windowState,
                  sourceZone: source.zone,
                  item: .splitGroup(
                      canonicalGroup.id,
                      title: canonicalGroup.title ?? "Split View"
                  )
              ) else { return false }
        let target: TabManagerDragTarget
        switch destination {
        case .regular(let spaceID):
            target = .init(
                container: .spaceRegular(spaceID),
                index: regularTabs.tabs(in: spaceID).count
            )
        case .pinned(let spaceID):
            target = .init(
                container: .spacePinned(spaceID),
                index: ordering.topLevelItems(for: spaceID).count
            )
        case .favorite(let profileID):
            target = .init(
                container: .favorite,
                index: ordering.favoriteItems(for: profileID).count
            )
        case .folder(let folderID, _, let spaceID):
            target = .init(
                container: .folder(folderID),
                index: ordering.groups(
                    for: spaceID,
                    folderID: folderID
                ).count
            )
        }
        return conversion.move(
            groupID: canonicalGroup.id,
            operation: DragOperation(
                payload: .splitGroup(canonicalGroup),
                scope: scope,
                fromContainer: source.container,
                toContainer: target.container,
                toIndex: target.index
            )
        )
    }

    private func source(
        for group: SplitGroup
    ) -> (zone: DropZoneID, container: TabDragManager.DragContainer)? {
        switch group.container {
        case .regularTabs(let spaceID?):
            return (.spaceRegular(spaceID), .spaceRegular(spaceID))
        case .favoriteSidebar:
            return (.favorite, .favorite)
        case .shortcutSidebar(let spaceID, _, let folderID, _):
            if let folderID {
                return (.folder(folderID), .folder(folderID))
            }
            return (.spacePinned(spaceID), .spacePinned(spaceID))
        case .regularTabs(nil):
            return nil
        }
    }

    private func isFavorite(_ group: SplitGroup, profileID: UUID) -> Bool {
        guard case .favoriteSidebar(let ownerID, _) = group.container else {
            return false
        }
        return ownerID == nil || ownerID == profileID
    }
}

private struct TabManagerDragTarget {
    let container: TabDragManager.DragContainer
    let index: Int
}
