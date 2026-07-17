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
}
