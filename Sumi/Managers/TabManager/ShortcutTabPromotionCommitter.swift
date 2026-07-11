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
        guard var preparedRetirement = retirement
            .prepareDeletedPinRetirement(plan.pinID) else {
            preconditionFailure("Preflighted shortcut runtime disappeared")
        }
        membership.attach(tab)
        regularTabs.insert(tab, in: plan.targetSpaceID, at: plan.targetIndex)

        preparedRetirement.result.merge(
            ShortcutLiveTabRetirementResult(
                windowStatesNeedingPersistence: windows.apply(
                    plan: plan,
                    split: split
                )
            )
        )
        return PreparedShortcutTabPromotion(
            tab: tab,
            retirement: preparedRetirement
        )
    }

    func finish(
        _ prepared: PreparedShortcutTabPromotion
    ) -> ShortcutTabPromotionResult {
        retirement.finishAfterCurrentBatch(prepared.retirement)
        return ShortcutTabPromotionResult(
            tab: prepared.tab,
            retirement: prepared.retirement.result
        )
    }
}
