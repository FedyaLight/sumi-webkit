import Foundation

/// Publishes a dropped URL's durable pin, live residence, and final window
/// selection as one structural transaction.
@MainActor
final class ShortcutURLInsertionTransaction {
    private let store: ShortcutPinStoreOwner
    private let activation: any ShortcutPresentationActivating
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        store: ShortcutPinStoreOwner,
        activation: any ShortcutPresentationActivating,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.store = store
        self.activation = activation
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    func insert(
        _ proposedPin: ShortcutPin,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState,
        activate: @escaping @MainActor (Tab) -> Void
    ) -> Bool {
        structuralLookup.withTransaction {
            structuralMutations.withReversibleSideEffects {
                guard let pin = store.insert(
                    proposedPin,
                    at: placement.index,
                    openTargetFolder: placement.openTargetFolder
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
        }
    }
}
