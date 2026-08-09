import Foundation
import SumiDomain

/// Context-menu target queries that do not mutate the tab graph.
@MainActor
final class SidebarRegularTabTargetQuery {
    private let splitGroups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let favorite: FavoriteShortcutPlacementOwner

    init(
        splitGroups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        favorite: FavoriteShortcutPlacementOwner
    ) {
        self.splitGroups = splitGroups
        self.pins = pins
        self.folders = folders
        self.favorite = favorite
    }

    func splitGroup(containing memberID: SplitMemberID) -> SplitGroup? {
        splitGroups.group(containing: memberID)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        pins.shortcutPin(by: id)
    }

    func userFolders(for spaceID: UUID) -> [TabFolder] {
        folders.folders(for: spaceID)
            .filter { !$0.isLiveFolder }
    }

    func canAddToFavorite(
        _ tab: Tab,
        in space: Space,
        windowState: BrowserWindowState
    ) -> Bool {
        guard tab.isPinned == false, tab.isSpacePinned == false else {
            return false
        }
        return favorite.canAddURL(
            tab.url,
            using: FavoriteShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }
}
