import Foundation

@MainActor
final class ShortcutLiveFolderPlacementReconciler {
    struct Source: Equatable {
        let folderID: UUID
        let index: Int
    }

    private let pins: ShortcutPinCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection

    init(
        pins: ShortcutPinCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.pins = pins
        self.runtimeConnection = runtimeConnection
    }

    func isCurrent(_ pin: ShortcutPin) -> Bool {
        pins.shortcutPin(by: pin.id) === pin
    }

    func isLiveFolder(_ folderID: UUID) -> Bool {
        runtimeConnection.current?.isLiveFolder(folderID) == true
    }

    func source(for pin: ShortcutPin) -> Source? {
        guard let folderID = pin.folderId, isLiveFolder(folderID) else {
            return nil
        }
        return Source(folderID: folderID, index: pin.index)
    }

    func reconcileMove(_ pin: ShortcutPin, from source: Source?) {
        guard let source,
              pin.folderId != source.folderID || pin.index != source.index else {
            return
        }
        runtimeConnection.current?.reconcileLiveFolderItemMove(
            shortcutPinID: pin.id,
            fromFolderID: source.folderID,
            toFolderID: pin.folderId,
            targetIndex: pin.index
        )
    }

    func reconcileReorder(
        _ pin: ShortcutPin,
        in folderID: UUID,
        spaceID: UUID
    ) {
        guard let targetIndex = pins.folderPinnedPins(
            for: folderID,
            in: spaceID
        ).firstIndex(where: { $0.id == pin.id }) else {
            return
        }
        runtimeConnection.current?.reconcileLiveFolderItemMove(
            shortcutPinID: pin.id,
            fromFolderID: folderID,
            toFolderID: folderID,
            targetIndex: targetIndex
        )
    }
}
