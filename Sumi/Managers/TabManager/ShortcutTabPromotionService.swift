import Foundation

/// Public promotion workflow. Planning, structural commit and window
/// reconciliation remain independently testable collaborators.
@MainActor
final class ShortcutTabPromotionService {
    private let planner: ShortcutTabPromotionPlanner
    private let committer: ShortcutTabPromotionCommitter
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        planner: ShortcutTabPromotionPlanner,
        committer: ShortcutTabPromotionCommitter,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.planner = planner
        self.committer = committer
        self.structuralLookup = structuralLookup
    }

    convenience init(tabManager: TabManager) {
        let windowTransition = ShortcutTabPromotionWindowTransition(
            registry: tabManager.liveShortcutTabs,
            membership: tabManager.tabCollectionMembershipOwner
        )
        self.init(
            planner: ShortcutTabPromotionPlanner(
                registry: tabManager.liveShortcutTabs,
                spaces: tabManager.spaceStateOwner,
                splitGroups: tabManager.splitGroupStore,
                tabFactory: tabManager.tabFactory,
                runtimePorts: { [weak tabManager] in tabManager?.runtimePorts }
            ),
            committer: ShortcutTabPromotionCommitter(
                registry: tabManager.liveShortcutTabs,
                retirement: tabManager.shortcutLiveTabRetirement,
                membership: tabManager.tabCollectionMembershipOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                windows: windowTransition
            ),
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }

    func promote(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> ShortcutTabPromotionResult? {
        guard let plan = preparePromotion(
            pin,
            into: targetSpaceId,
            at: targetIndex,
            preferredWindowId: preferredWindowId,
            allowsGroupedPin: false
        ) else { return nil }
        let prepared = structuralLookup.withTransaction {
            committer.commit(plan, split: .none)
        }
        return committer.finish(prepared)
    }

    func preparePromotion(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil,
        allowsGroupedPin: Bool
    ) -> ShortcutTabPromotionPlan? {
        planner.prepare(
            pin,
            targetSpaceID: targetSpaceId,
            targetIndex: targetIndex,
            preferredWindowID: preferredWindowId,
            allowsGroupedPin: allowsGroupedPin
        )
    }

    func commit(
        _ plan: ShortcutTabPromotionPlan,
        splitTransition: ShortcutTabPromotionSplitTransition
    ) -> PreparedShortcutTabPromotion {
        committer.commit(plan, split: splitTransition)
    }

    func finish(
        _ prepared: PreparedShortcutTabPromotion
    ) -> ShortcutTabPromotionResult {
        committer.finish(prepared)
    }
}
