import Foundation

/// Publishes a dropped URL's durable pin, live residence, and final window
/// selection as one structural transaction.
@MainActor
final class ShortcutURLInsertionTransaction {
    private let store: ShortcutPinStoreOwner
    private let activation: any ShortcutPresentationActivating
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let folderOpenState: TabFolderOpenStateService

    init(
        store: ShortcutPinStoreOwner,
        activation: any ShortcutPresentationActivating,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        folderOpenState: TabFolderOpenStateService
    ) {
        self.store = store
        self.activation = activation
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
        self.folderOpenState = folderOpenState
    }

    func insert(
        _ proposedPin: ShortcutPin,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState,
        activate: @escaping @MainActor (Tab) -> Void
    ) -> Bool {
        structuralLookup.withTransaction {
            let committed = structuralMutations.withReversibleSideEffects {
                guard let pin = store.insert(
                    proposedPin,
                    at: placement.index,
                    openTargetFolder: false
                ) else { return false }
                var preparedTab: Tab?
                let accepted = activation.withActivation(
                    pin,
                    in: windowState.id,
                    presentationSpaceID: placement.spaceID
                        ?? windowState.currentSpaceId
                ) { liveTab in
                    preparedTab = liveTab
                    return true
                }
                guard accepted, let liveTab = preparedTab else { return false }
                _ = WindowTabSelectionStateApplicator.apply(
                    liveTab,
                    to: windowState,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
                structuralLookup.runAfterCurrentBatch {
                    activate(liveTab)
                }
                return true
            }
            if committed,
               placement.openTargetFolder,
               let folderID = placement.folderID {
                folderOpenState.openFolderIfNeeded(folderID)
            }
            return committed
        }
    }
}
