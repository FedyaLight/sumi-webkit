import Foundation

/// Owns the identity and residence preflight for Glance adoption. Only a new
/// physical residence enters the admitted commit phase.
@MainActor
final class GlanceTabAdoptionTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let committer: GlanceTabAdoptionCommitter

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        committer: GlanceTabAdoptionCommitter
    ) {
        self.structuralLookup = structuralLookup
        self.membership = membership
        self.regularTabs = regularTabs
        self.committer = committer
    }

    func adopt(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space?
    ) -> Tab? {
        structuralLookup.withTransaction {
            if let spaceID = tab.spaceId,
               regularTabs.containsIdentical(tab, in: spaceID) {
                return tab
            }
            guard membership.contains(tab) == false else { return nil }
            return committer.commit(tab, sourceTab: sourceTab, in: space)
        }
    }
}
