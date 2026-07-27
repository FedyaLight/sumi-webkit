import Foundation
import SumiDomain

@MainActor
final class ShortcutPinRetirementCommitter {
    private let retirement: ShortcutLiveTabRetirementService
    private let runtimeConnection: TabRuntimePortConnection
    private let store: ShortcutPinStoreOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        retirement: ShortcutLiveTabRetirementService,
        runtimeConnection: TabRuntimePortConnection,
        store: ShortcutPinStoreOwner,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.retirement = retirement
        self.runtimeConnection = runtimeConnection
        self.store = store
        self.structuralMutations = structuralMutations
    }

    func commit(
        _ pins: [ShortcutPin],
        presentNotification: Bool = true
    ) -> Bool {
        let pinIDs = Set(pins.map(\.id))
        guard pinIDs.count == pins.count,
              let claim = retirement.prepareDeletedPinRetirements(pinIDs)
        else { return false }
        pins.forEach { pin in
            runtimeConnection.current?.captureDeletedShortcutLauncher(pin)
            store.removeFromContainers(pin)
        }
        retirement.finishAfterCurrentBatch(claim)
        structuralMutations.schedulePersistence()
        if presentNotification, pins.isEmpty == false {
            runtimeConnection.current?.notifications()?
                .presentSavedTabDeletionNotification(
                    tabCount: pins.count,
                    in: nil
                )
        }
        return true
    }
}
