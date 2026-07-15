import Foundation
import SumiDomain

/// Captures and revalidates the durable half of regular-tab conversion.
/// Mutation is intentionally owned by `RegularTabShortcutConversionService`,
/// where pin insertion, split replacement and runtime transition share one
/// transaction.
@MainActor
final class RegularTabShortcutStructureTransition {
    private let regularTabs: RegularTabCollectionOwner
    private let splitGroupStore: SplitGroupStore
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        regularTabs: RegularTabCollectionOwner,
        splitGroupStore: SplitGroupStore,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.regularTabs = regularTabs
        self.splitGroupStore = splitGroupStore
        self.structuralLookup = structuralLookup
    }

    func prepare(_ tab: Tab) -> RegularTabShortcutStructurePlan? {
        guard regularTabs.contains(tab),
              tab.isShortcutLiveInstance == false else {
            return nil
        }
        let sourceMemberID = SplitMemberID.regularTab(tab.id)
        return RegularTabShortcutStructurePlan(
            sourceTabID: tab.id,
            expectedSplitGroups: splitGroupStore.groups,
            sourceSplitGroup: splitGroupStore.group(
                containing: sourceMemberID
            ),
            structuralRevision: structuralLookup.mutationRevision
        )
    }

    func isCurrent(
        _ plan: RegularTabShortcutStructurePlan,
        for tab: Tab
    ) -> Bool {
        guard plan.sourceTabID == tab.id,
              regularTabs.contains(tab),
              tab.isShortcutLiveInstance == false,
              structuralLookup.mutationRevision == plan.structuralRevision,
              splitGroupStore.groups == plan.expectedSplitGroups else {
            return false
        }

        return splitGroupStore.group(
            containing: plan.sourceMemberID
        ) == plan.sourceSplitGroup
    }
}
