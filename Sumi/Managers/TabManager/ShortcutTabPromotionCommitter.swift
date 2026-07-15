import Foundation

/// Commits a preflighted registry lease into the regular collection and stages
/// retirement of all other window-local instances.
@MainActor
final class ShortcutTabPromotionCommitter {
    private let registry: LiveShortcutTabRegistry
    private let retirement: ShortcutLiveTabRetirementService
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let windows: ShortcutTabPromotionWindowTransition

    init(
        registry: LiveShortcutTabRegistry,
        retirement: ShortcutLiveTabRetirementService,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        windows: ShortcutTabPromotionWindowTransition
    ) {
        self.registry = registry
        self.retirement = retirement
        self.membership = membership
        self.regularTabs = regularTabs
        self.windows = windows
    }

    func commit(
        _ plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition
    ) -> PreparedShortcutTabPromotion {
        let tab = plan.tab
        let targetWindows = windows.project(plan: plan, split: split)
        if let chosen = plan.chosenEntry {
            guard registry.remove(
                pinId: plan.pinID,
                in: chosen.windowId
            )?.tab === tab else {
                preconditionFailure("Prepared shortcut lease changed")
            }
            tab.clearShortcutBinding()
            tab.folderId = nil
            tab.isPinned = false
            tab.isSpacePinned = false
        }
        guard let preparedRetirement = retirement
            .prepareDeletedPinRetirement(
                plan.pinID,
                targetWindowStates: targetWindows
            ) else {
            preconditionFailure("Preflighted shortcut runtime disappeared")
        }
        membership.attach(tab)
        regularTabs.insert(tab, in: plan.targetSpaceID, at: plan.targetIndex)

        return PreparedShortcutTabPromotion(
            tab: tab,
            retirement: preparedRetirement,
            result: preparedRetirement.result
        )
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
