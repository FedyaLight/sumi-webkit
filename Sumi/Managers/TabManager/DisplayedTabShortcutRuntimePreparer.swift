import Foundation

@MainActor
final class DisplayedTabShortcutRuntimePreparer {
    private let membership: TabCollectionMembershipOwner
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let regularTabs: RegularTabCollectionOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let reconciler: RegularTabShortcutWindowReconciler

    init(
        membership: TabCollectionMembershipOwner,
        containerRemoval: ShortcutContainerRemovalOwner,
        regularTabs: RegularTabCollectionOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.membership = membership
        self.containerRemoval = containerRemoval
        self.regularTabs = regularTabs
        self.structuralLookup = structuralLookup
        reconciler = RegularTabShortcutWindowReconciler(
            regularTabs: regularTabs
        )
    }

    func prepare(
        _ binding: PreparedDisplayedTabShortcutBinding,
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDisplayedTabShortcutConversion
    ) -> DisplayedTabShortcutRuntimeTransaction? {
        let attachment = authorization.plan.runtimeAttachment
        let admittedWindowIDs = Set(authorization.plan.presentationWindowIds)
        guard attachment.isCurrent(),
              Set(binding.liveTabsByWindowID.keys) == admittedWindowIDs,
              Set(binding.terminalIdentitiesByWindowID.keys)
                == admittedWindowIDs,
              let membershipWitness = DisplayedTabShortcutMembershipWitness(
                membership: membership,
                source: binding.sourceTab,
                freshTabs: binding.freshTabs.map(\.0)
              ),
              let runtime = attachment.currentRegistry(),
              let windows = reconciler.prepareContribution(
                originalTabId: binding.sourceTab.id,
                splitTransition: transition,
                sourceSpaceId: binding.sourceSpaceID,
                liveTabsByWindowId: binding.liveTabsByWindowID,
                terminalIdentitiesByWindowId: binding
                    .terminalIdentitiesByWindowID,
                selectedWindowIds: Set(authorization.plan.selectedWindowIds),
                using: runtime
              ),
              attachment.isCurrent() else { return nil }
        return DisplayedTabShortcutRuntimeTransaction(
            windows: windows,
            binding: binding,
            membershipWitness: membershipWitness,
            containerRemoval: containerRemoval,
            regularTabs: regularTabs,
            structuralLookup: structuralLookup,
            runtimeAttachment: attachment
        )
    }
}
