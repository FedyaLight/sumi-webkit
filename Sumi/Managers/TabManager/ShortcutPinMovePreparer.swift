import Foundation
import SumiDomain

@MainActor
final class ShortcutPinMovePreparer {
    private let runtimeConnection: TabRuntimePortConnection
    private let pins: ShortcutPinCollectionStateOwner
    private let store: ShortcutPinStoreOwner
    private let bindings: ShortcutTabBindingSynchronizer

    init(
        runtimeConnection: TabRuntimePortConnection,
        pins: ShortcutPinCollectionStateOwner,
        store: ShortcutPinStoreOwner,
        bindings: ShortcutTabBindingSynchronizer
    ) {
        self.runtimeConnection = runtimeConnection
        self.pins = pins
        self.store = store
        self.bindings = bindings
    }

    func prepare(
        _ pin: ShortcutPin,
        role: ShortcutPinRole,
        profileID: UUID?,
        spaceID: UUID?,
        folderID: UUID?,
        index: Int
    ) -> LiveShortcutPresentationRefreshAdmission? {
        guard pins.shortcutPin(by: pin.id) === pin else { return nil }
        if let folderID,
           runtimeConnection.current?.isLiveFolder(folderID) == true {
            return nil
        }
        guard let preview = store.previewMove(
            pin,
            to: role,
            profileId: profileID,
            spaceId: spaceID,
            folderId: folderID,
            proposedIndex: index
        ), let admission = bindings.refreshAdmission(for: preview) else {
            return nil
        }
        return admission
    }
}
