import Foundation

extension ShortcutPinToRegularTabService {
    convenience init(tabManager: TabManager) {
        let promotion = tabManager.shortcutTabPromotion
        let transaction = ShortcutPinRegularConversionTransaction(
            promotion: promotion,
            splitMutations: tabManager.splitGroupMutations,
            removePin: { [weak tabManager] pin in
                tabManager?.shortcutPinStoreOwner.removeFromContainers(pin)
            },
            schedulePersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        self.init(
            promotion: promotion,
            splitGroups: tabManager.splitGroupStore,
            canonicalPin: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: $0)
            },
            transaction: transaction
        )
    }
}
