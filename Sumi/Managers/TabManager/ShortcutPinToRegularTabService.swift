import Foundation
import SumiDomain

/// Converts a canonical pin through a preflighted promotion plan and an exact
/// split transition. Transaction mechanics live in a dedicated collaborator.
@MainActor
final class ShortcutPinToRegularTabService {
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

    @discardableResult
    func convert(
        _ candidatePin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        guard let pin = admission.canonicalPin(for: candidatePin),
              let plan = promotion.preparePromotion(
                  pin,
                  into: targetSpaceId,
                  at: targetIndex,
                  preferredWindowId: preferredWindowId,
                  allowsGroupedPin: true
              ) else { return false }

        guard case .admitted(let split) = admission.splitOutcome(
            pinID: pin.id,
            promotedTabID: plan.tab.id,
            targetSpaceID: targetSpaceId
        ) else {
            _ = plan.placement.cancel()
            return false
        }
        return transaction.commit(pin: pin, plan: plan, split: split)
    }

    func convertGroup(
        _ group: SplitGroup,
        into targetSpaceID: UUID,
        at targetIndex: Int,
        preferredWindowID: UUID?
    ) -> Bool {
        guard let groupPins = admission.canonicalGroupPins(for: group)
        else { return false }
        return transaction.commitGroup(
            group,
            pins: groupPins,
            into: targetSpaceID,
            at: targetIndex,
            preferredWindowID: preferredWindowID
        )
    }
}
