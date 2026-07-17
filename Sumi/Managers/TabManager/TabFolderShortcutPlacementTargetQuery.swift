import Foundation

@MainActor
final class TabFolderShortcutPlacementTargetQuery {
    struct Target {
        let folderID: UUID
        let spaceID: UUID
        let insertionIndex: Int
        let sourcePin: ShortcutPin?
    }

    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection

    init(
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.folders = folders
        self.pins = pins
        self.runtimeConnection = runtimeConnection
    }

    func target(for folderID: UUID, moving tab: Tab) -> Target? {
        guard let folder = folders.folder(by: folderID),
              runtimeConnection.current?.isLiveFolder(folderID) != true else {
            return nil
        }
        return Target(
            folderID: folder.id,
            spaceID: folder.spaceId,
            insertionIndex: pins.folderPinnedPins(
                for: folder.id,
                in: folder.spaceId
            ).count,
            sourcePin: tab.shortcutPinId.flatMap(pins.shortcutPin(by:))
        )
    }
}
