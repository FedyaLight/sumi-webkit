import Foundation

@MainActor
struct DisplayedTabShortcutMembershipWitness {
    private let membership: TabCollectionMembershipOwner
    private let source: Tab
    private let freshTabs: [Tab]
    private let allTabs: [Tab]
    private let allIDs, freshIDs: Set<UUID>

    init?(
        membership: TabCollectionMembershipOwner,
        source: Tab,
        freshTabs: [Tab]
    ) {
        let allTabs = [source] + freshTabs
        let allIDs = Set(allTabs.map(\.id))
        guard allIDs.count == allTabs.count,
              Set(allTabs.map(ObjectIdentifier.init)).count == allTabs.count
        else { return nil }
        self.membership = membership
        self.source = source
        self.freshTabs = freshTabs
        self.allTabs = allTabs
        self.allIDs = allIDs
        freshIDs = Set(freshTabs.map(\.id))
        guard preparedModelIsExact() else { return nil }
    }

    func prepareFreshTabsForRuntime() { membership.prepareForRuntime(freshTabs) }

    func preparedModelIsExact() -> Bool {
        membership.hasExactIdentityResidences([source], scopedTo: allIDs)
            && membership.lookupContainsExact(source)
            && membership.lookupContainsNone(of: freshIDs)
    }

    func sourceRemovalIsExact() -> Bool {
        membership.hasExactIdentityResidences([], scopedTo: allIDs)
            && membership.lookupContainsExact(source)
            && membership.lookupContainsNone(of: freshIDs)
    }

    func stagedResidencesAreExact() -> Bool {
        membership.hasExactIdentityResidences(allTabs, scopedTo: allIDs)
            && membership.lookupContainsExact(source)
            && membership.lookupContainsNone(of: freshIDs)
    }

    func publishFreshAttachments() -> Bool {
        guard membership.hasExactIdentityResidences(
            allTabs,
            scopedTo: allIDs
        ) else { return false }
        return membership.attachPreparedIfAbsent(
            freshTabs,
            retainingExact: source
        )
    }
}
