import Foundation
import SumiDomain

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

    static func compose(
        registry: LiveShortcutTabRegistry,
        spaces: TabSpaceCollectionStateOwner,
        splitGroups: SplitGroupStore,
        tabFactory: TabFactory,
        regularTabs: RegularTabCollectionOwner,
        runtimeConnection: TabRuntimePortConnection,
        retirement: ShortcutLiveTabRetirementService,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) -> ShortcutTabPromotionService {
        let windowTransition = ShortcutTabPromotionWindowTransition(
            registry: registry,
            membership: membership
        )
        return ShortcutTabPromotionService(
            planner: ShortcutTabPromotionPlanner(
                spaces: spaces,
                splitGroups: splitGroups,
                regularTabs: regularTabs,
                sources: ShortcutTabPromotionSourcePlanner(
                    registry: registry,
                    tabFactory: tabFactory,
                    runtimeConnection: runtimeConnection
                )
            ),
            committer: ShortcutTabPromotionCommitter(
                registry: registry,
                retirement: retirement,
                membership: membership,
                windows: windowTransition
            ),
            structuralLookup: structuralLookup
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
        guard let prepared else { return nil }
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
    ) -> PreparedShortcutTabPromotion? {
        committer.commit(plan, split: splitTransition)
    }

    func finish(
        _ prepared: PreparedShortcutTabPromotion
    ) -> ShortcutTabPromotionResult {
        committer.finish(prepared)
    }

    func commitGroup(
        _ plans: [ShortcutTabPromotionPlan],
        groupID: UUID,
        memberByPinID: [UUID: SplitMemberID]
    ) -> PreparedShortcutTabGroupPromotion? {
        committer.commitGroup(
            plans,
            groupID: groupID,
            memberByPinID: memberByPinID
        )
    }

    func finishGroup(_ prepared: PreparedShortcutTabGroupPromotion) {
        committer.finishGroup(prepared)
    }
}
