import Foundation
import SumiDomain

/// Commits a preflighted registry lease into the regular collection and stages
/// retirement of all other window-local instances.
@MainActor
final class ShortcutTabPromotionCommitter {
    private let registry: LiveShortcutTabRegistry
    private let retirement: ShortcutLiveTabRetirementService
    private let membership: TabCollectionMembershipOwner
    private let windows: ShortcutTabPromotionWindowTransition

    init(
        registry: LiveShortcutTabRegistry,
        retirement: ShortcutLiveTabRetirementService,
        membership: TabCollectionMembershipOwner,
        windows: ShortcutTabPromotionWindowTransition
    ) {
        self.registry = registry
        self.retirement = retirement
        self.membership = membership
        self.windows = windows
    }

    func commit(
        _ plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition
    ) -> PreparedShortcutTabPromotion? {
        let tab = plan.tab
        let targetWindows = windows.project(plan: plan, split: split)
        let registrySnapshot = registry.mutationSnapshot
        let shortcutPinID = tab.shortcutPinId
        let shortcutPinRole = tab.shortcutPinRole
        let wasShortcutLiveInstance = tab.isShortcutLiveInstance
        if let chosen = plan.chosenEntry {
            guard registry.remove(
                pinId: plan.pinID,
                in: chosen.windowId
            )?.tab === tab else {
                _ = plan.placement.cancel()
                return nil
            }
            tab.clearShortcutBinding()
        }
        guard plan.placement.stage() else {
            registry.restoreMutationSnapshot(registrySnapshot)
            restoreShortcutBinding(
                tab,
                pinID: shortcutPinID,
                role: shortcutPinRole,
                isLive: wasShortcutLiveInstance
            )
            return nil
        }
        guard let preparedRetirement = retirement
            .prepareDeletedPinRetirement(
                plan.pinID,
                targetWindowStates: targetWindows
            ) else {
            precondition(plan.placement.rollback())
            registry.restoreMutationSnapshot(registrySnapshot)
            restoreShortcutBinding(
                tab,
                pinID: shortcutPinID,
                role: shortcutPinRole,
                isLive: wasShortcutLiveInstance
            )
            return nil
        }
        guard plan.placement.finish(publishing: {
            membership.attach(tab)
        }) else {
            precondition(plan.placement.rollback())
            registry.restoreMutationSnapshot(registrySnapshot)
            restoreShortcutBinding(
                tab,
                pinID: shortcutPinID,
                role: shortcutPinRole,
                isLive: wasShortcutLiveInstance
            )
            return nil
        }

        return PreparedShortcutTabPromotion(
            tab: tab,
            retirement: preparedRetirement,
            result: preparedRetirement.result
        )
    }

    private func restoreShortcutBinding(
        _ tab: Tab,
        pinID: UUID?,
        role: ShortcutPinRole?,
        isLive: Bool
    ) {
        tab.shortcutPinId = pinID
        tab.shortcutPinRole = role
        tab.isShortcutLiveInstance = isLive
    }

    func finish(
        _ prepared: PreparedShortcutTabPromotion
    ) -> ShortcutTabPromotionResult {
        retirement.finishAfterCurrentBatch(prepared.retirement)
        return ShortcutTabPromotionResult(
            tab: prepared.tab,
            retirement: prepared.result
        )
    }

    func commitGroup(
        _ plans: [ShortcutTabPromotionPlan],
        groupID: UUID,
        memberByPinID: [UUID: SplitMemberID]
    ) -> PreparedShortcutTabGroupPromotion? {
        guard !plans.isEmpty,
              Set(plans.map(\.pinID)).count == plans.count,
              Set(memberByPinID.keys) == Set(plans.map(\.pinID))
        else {
            _ = PreparedRegularTabPlacement.cancelAggregate(
                plans.map(\.placement)
            )
            return nil
        }

        let registrySnapshot = registry.mutationSnapshot
        let bindings = plans.map { plan in
            (
                tab: plan.tab,
                pinID: plan.tab.shortcutPinId,
                role: plan.tab.shortcutPinRole,
                isLive: plan.tab.isShortcutLiveInstance
            )
        }
        for plan in plans where plan.chosenEntry != nil {
            guard let chosen = plan.chosenEntry,
                  registry.remove(
                      pinId: plan.pinID,
                      in: chosen.windowId
                  )?.tab === plan.tab else {
                registry.restoreMutationSnapshot(registrySnapshot)
                restoreBindings(bindings)
                _ = PreparedRegularTabPlacement.cancelAggregate(
                    plans.map(\.placement)
                )
                return nil
            }
            plan.tab.clearShortcutBinding()
        }

        let placements = plans.map(\.placement)
        guard PreparedRegularTabPlacement.stageAggregate(placements) else {
            registry.restoreMutationSnapshot(registrySnapshot)
            restoreBindings(bindings)
            return nil
        }
        let targetWindows = windows.projectGroup(
            plans: plans,
            groupID: groupID,
            memberByPinID: memberByPinID
        )
        guard let preparedRetirement = retirement
            .prepareDeletedPinRetirements(
                Set(plans.map(\.pinID)),
                targetWindowStates: targetWindows
            ) else {
            precondition(
                PreparedRegularTabPlacement.rollbackAggregate(placements)
            )
            registry.restoreMutationSnapshot(registrySnapshot)
            restoreBindings(bindings)
            return nil
        }
        precondition(
            PreparedRegularTabPlacement.finishAggregate(
                placements,
                publishing: { [membership] in
                    plans.forEach { membership.attach($0.tab) }
                }
            ),
            "Staged split promotion lost its regular-tab admission"
        )
        return PreparedShortcutTabGroupPromotion(
            retirement: preparedRetirement
        )
    }

    func finishGroup(_ prepared: PreparedShortcutTabGroupPromotion) {
        retirement.finishAfterCurrentBatch(prepared.retirement)
    }

    private func restoreBindings(
        _ bindings: [(
            tab: Tab,
            pinID: UUID?,
            role: ShortcutPinRole?,
            isLive: Bool
        )]
    ) {
        bindings.forEach {
            restoreShortcutBinding(
                $0.tab,
                pinID: $0.pinID,
                role: $0.role,
                isLive: $0.isLive
            )
        }
    }
}
