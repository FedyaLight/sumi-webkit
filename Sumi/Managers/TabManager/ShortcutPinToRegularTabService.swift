import Foundation

/// Promotes a shortcut to one regular tab and removes its launcher in the same
/// structural transaction before completing runtime retirement.
@MainActor
final class ShortcutPinToRegularTabService {
    private let promotion: ShortcutTabPromotionService
    private let removeShortcutPin: (ShortcutPin) -> Void
    private let scheduleStructuralPersistence: () -> Void
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        promotion: ShortcutTabPromotionService,
        removeShortcutPin: @escaping (ShortcutPin) -> Void,
        scheduleStructuralPersistence: @escaping () -> Void,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.promotion = promotion
        self.removeShortcutPin = removeShortcutPin
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
        self.structuralLookup = structuralLookup
    }

    convenience init(tabManager: TabManager) {
        self.init(
            promotion: tabManager.shortcutTabPromotion,
            removeShortcutPin: { [weak tabManager] pin in
                tabManager?.shortcutPinStoreOwner.removeFromContainers(pin)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence
                    .scheduleStructuralPersistence()
            },
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }

    @discardableResult
    func convert(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        let prepared: PreparedShortcutTabPromotion? = structuralLookup
            .withTransaction {
                guard let prepared = promotion.preparePromotion(
                    pin,
                    into: targetSpaceId,
                    at: targetIndex,
                    preferredWindowId: preferredWindowId
                ) else { return nil }
                removeShortcutPin(pin)
                return prepared
            }
        guard let prepared else { return false }
        _ = promotion.finish(prepared)
        scheduleStructuralPersistence()
        return true
    }
}
