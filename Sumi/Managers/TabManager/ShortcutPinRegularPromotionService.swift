import Foundation

/// Promotes one canonical shortcut pin through an admitted split transition.
@MainActor
final class ShortcutPinRegularPromotionService {
    private let promotion: ShortcutTabPromotionService
    private let admission: ShortcutPinPromotionAdmission
    private let transaction: ShortcutPinRegularConversionTransaction

    init(
        promotion: ShortcutTabPromotionService,
        admission: ShortcutPinPromotionAdmission,
        transaction: ShortcutPinRegularConversionTransaction
    ) {
        self.promotion = promotion
        self.admission = admission
        self.transaction = transaction
    }

    func promote(
        _ candidatePin: ShortcutPin,
        into targetSpaceID: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> ShortcutTabPromotionResult? {
        guard let pin = admission.canonicalPin(for: candidatePin),
              let plan = promotion.preparePromotion(
                  pin,
                  into: targetSpaceID,
                  at: targetIndex,
                  preferredWindowId: preferredWindowId,
                  allowsGroupedPin: true
              ) else { return nil }

        guard case .admitted(let split) = admission.splitOutcome(
            pinID: pin.id,
            promotedTabID: plan.tab.id,
            targetSpaceID: targetSpaceID
        ) else {
            _ = plan.placement.cancel()
            return nil
        }
        return transaction.commit(pin: pin, plan: plan, split: split)
    }
}
