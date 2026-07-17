import Foundation
import SumiDomain

/// Converts a canonical pin through a preflighted promotion plan and an exact
/// split transition. Transaction mechanics live in a dedicated collaborator.
@MainActor
final class ShortcutPinToRegularTabService {
    private let promotion: ShortcutTabPromotionService
    private let splitGroups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let transaction: ShortcutPinRegularConversionTransaction

    init(
        promotion: ShortcutTabPromotionService,
        splitGroups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner,
        transaction: ShortcutPinRegularConversionTransaction
    ) {
        self.promotion = promotion
        self.splitGroups = splitGroups
        self.pins = pins
        self.transaction = transaction
    }

    @discardableResult
    func convert(
        _ candidatePin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        guard let pin = pins.shortcutPin(by: candidatePin.id),
              let plan = promotion.preparePromotion(
                  pin,
                  into: targetSpaceId,
                  at: targetIndex,
                  preferredWindowId: preferredWindowId,
                  allowsGroupedPin: true
              ) else { return false }

        let group = splitGroups.group(containing: .shortcutPin(pin.id))
        let split = group.flatMap {
            ShortcutPinRegularSplitTransitionPlanner().transition(
                group: $0,
                pinID: pin.id,
                promotedTabID: plan.tab.id,
                targetSpaceID: targetSpaceId
            )
        }
        guard group == nil || split != nil else {
            _ = plan.placement.cancel()
            return false
        }
        return transaction.commit(pin: pin, plan: plan, split: split)
    }
}
