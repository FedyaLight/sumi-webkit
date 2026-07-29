import Foundation
import SumiDomain

/// Commits exact split mutation and runtime promotion in one structural batch,
/// removes the saved launcher, then persists once.
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
    ) -> ShortcutTabPromotionResult? {
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
            return nil
        }
        guard let prepared else { return nil }
        let result = promotion.finish(prepared)
        persistence.scheduleStructuralPersistence()
        return result
    }

    func commitGroup(
        _ group: SplitGroup,
        pins: [ShortcutPin],
        into targetSpaceID: UUID,
        at targetIndex: Int,
        preferredWindowID: UUID?
    ) -> Bool {
        guard group.container.isShortcutSidebar,
              pins.map(\.id).map(SplitMemberID.shortcutPin)
                == group.memberIDs else { return false }

        var plans: [ShortcutTabPromotionPlan] = []
        for (offset, pin) in pins.enumerated() {
            guard let plan = promotion.preparePromotion(
                pin,
                into: targetSpaceID,
                at: targetIndex + offset,
                preferredWindowId: preferredWindowID,
                allowsGroupedPin: true
            ) else {
                _ = PreparedRegularTabPlacement.cancelAggregate(
                    plans.map(\.placement)
                )
                return false
            }
            plans.append(plan)
        }

        var tree = group.layoutTree
        var memberByPinID: [UUID: SplitMemberID] = [:]
        for plan in plans {
            let memberID = SplitMemberID.regularTab(plan.tab.id)
            memberByPinID[plan.pinID] = memberID
            guard let replacement = tree.replacingMember(
                .shortcutPin(plan.pinID),
                with: memberID
            ) else {
                _ = PreparedRegularTabPlacement.cancelAggregate(
                    plans.map(\.placement)
                )
                return false
            }
            tree = replacement
        }
        guard let replacementGroup = SplitGroup(
            id: group.id,
            layoutKind: group.layoutKind,
            layoutTree: tree,
            container: .regularTabs(spaceId: targetSpaceID),
            title: group.title,
            iconAsset: group.iconAsset
        ) else {
            _ = PreparedRegularTabPlacement.cancelAggregate(
                plans.map(\.placement)
            )
            return false
        }

        var prepared: PreparedShortcutTabGroupPromotion?
        let committed = splitMutations.replaceAtomically(
            group,
            with: replacementGroup,
            persist: false
        ) { [self] in
            guard let groupPromotion = promotion.commitGroup(
                plans,
                groupID: group.id,
                memberByPinID: memberByPinID
            ) else { return false }
            prepared = groupPromotion
            pins.forEach(pinStore.removeFromContainers)
            return true
        }
        guard committed, let prepared else { return false }
        promotion.finishGroup(prepared)
        persistence.scheduleStructuralPersistence()
        return true
    }
}
