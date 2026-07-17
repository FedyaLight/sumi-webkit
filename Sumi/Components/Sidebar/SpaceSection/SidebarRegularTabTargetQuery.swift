import Foundation
import SumiDomain

/// Context-menu target queries that do not mutate the tab graph.
@MainActor
final class SidebarRegularTabTargetQuery {
    private let splitGroups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let liveFolders: SumiLiveFolderManager
    private let essentials: EssentialsShortcutPlacementOwner

    init(
        splitGroups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        liveFolders: SumiLiveFolderManager,
        essentials: EssentialsShortcutPlacementOwner
    ) {
        self.splitGroups = splitGroups
        self.pins = pins
        self.folders = folders
        self.liveFolders = liveFolders
        self.essentials = essentials
    }

    func splitGroup(containing memberID: SplitMemberID) -> SplitGroup? {
        splitGroups.group(containing: memberID)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        pins.shortcutPin(by: id)
    }

    func userFolders(for spaceID: UUID) -> [TabFolder] {
        folders.folders(for: spaceID)
            .filter { liveFolders.isLiveFolder($0.id) == false }
    }

    func canAddToEssentials(
        _ tab: Tab,
        in space: Space,
        windowState: BrowserWindowState
    ) -> Bool {
        guard tab.isPinned == false, tab.isSpacePinned == false else {
            return false
        }
        return essentials.canAddURL(
            tab.url,
            using: EssentialsShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }
}
