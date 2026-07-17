import Foundation

/// Commits pin removal, exact split mutation and runtime promotion in one
/// structural batch, then performs one durable persistence request.
@MainActor
final class ShortcutPinRegularConversionTransaction {
    private let promotion: ShortcutTabPromotionService
    private let splitMutations: SplitGroupMutationService
    private let pinStore: ShortcutPinStoreOwner
    private let persistence: TabStructuralPersistenceService
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        promotion: ShortcutTabPromotionService,
        splitMutations: SplitGroupMutationService,
        pinStore: ShortcutPinStoreOwner,
        persistence: TabStructuralPersistenceService,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.promotion = promotion
        self.splitMutations = splitMutations
        self.pinStore = pinStore
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    func commit(
        pin: ShortcutPin,
        plan: ShortcutTabPromotionPlan,
        split: ShortcutPinRegularSplitTransition?
    ) -> Bool {
        var prepared: PreparedShortcutTabPromotion?
        let applyPromotion: @MainActor () -> Bool = { [self] in
            guard let committedPromotion = promotion.commit(
                plan,
                splitTransition: split?.windows ?? .none
            ) else { return false }
            prepared = committedPromotion
            pinStore.removeFromContainers(pin)
            return true
        }

        let committed: Bool
        switch split?.mutation {
        case .replace(let expected, let replacement):
            committed = splitMutations.replaceAtomically(
                expected,
                with: replacement,
                persist: false,
                applying: applyPromotion
            )
        case .remove(let expected):
            committed = splitMutations.removeAtomically(
                expected,
                persist: false,
                applying: applyPromotion
            )
        case nil:
            committed = structuralLookup.withTransaction(applyPromotion)
        }

        guard committed else {
            _ = plan.placement.cancel()
            return false
        }
        guard let prepared else { return false }
        _ = promotion.finish(prepared)
        persistence.scheduleStructuralPersistence()
        return true
    }
}
