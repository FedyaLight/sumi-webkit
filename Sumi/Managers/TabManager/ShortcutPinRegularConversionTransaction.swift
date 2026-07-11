import Foundation

/// Commits pin removal, exact split mutation and runtime promotion in one
/// structural batch, then performs one durable persistence request.
@MainActor
final class ShortcutPinRegularConversionTransaction {
    private let promotion: ShortcutTabPromotionService
    private let splitMutations: SplitGroupMutationService
    private let removePin: (ShortcutPin) -> Void
    private let schedulePersistence: () -> Void
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        promotion: ShortcutTabPromotionService,
        splitMutations: SplitGroupMutationService,
        removePin: @escaping (ShortcutPin) -> Void,
        schedulePersistence: @escaping () -> Void,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.promotion = promotion
        self.splitMutations = splitMutations
        self.removePin = removePin
        self.schedulePersistence = schedulePersistence
        self.structuralLookup = structuralLookup
    }

    func commit(
        pin: ShortcutPin,
        plan: ShortcutTabPromotionPlan,
        split: ShortcutPinRegularSplitTransition?
    ) -> Bool {
        var prepared: PreparedShortcutTabPromotion?
        let applyPromotion: @MainActor () -> Void = { [self] in
            prepared = promotion.commit(
                plan,
                splitTransition: split?.windows ?? .none
            )
            removePin(pin)
        }

        let committed: Bool
        switch split?.mutation {
        case .replace(let expected, let replacement):
            committed = splitMutations.replace(
                expected,
                with: replacement,
                persist: false,
                alongside: applyPromotion
            )
        case .remove(let expected):
            committed = splitMutations.remove(
                expected,
                persist: false,
                alongside: applyPromotion
            )
        case nil:
            structuralLookup.withTransaction(applyPromotion)
            committed = prepared != nil
        }

        guard committed, let prepared else { return false }
        _ = promotion.finish(prepared)
        schedulePersistence()
        return true
    }
}
