import Foundation

/// Commits one prepared regular-tab residence and publishes its durable
/// structural membership. The enclosing transaction owns batching.
@MainActor
final class RegularTabResidencePublication {
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let persistence: TabStructuralPersistenceService

    init(
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.membership = membership
        self.regularTabs = regularTabs
        self.persistence = persistence
    }

    func publish(
        _ tab: Tab,
        regularInsertionIndex: Int?,
        admissionProfileIDs: Set<UUID>?
    ) -> Bool {
        guard let spaceID = tab.spaceId else {
            RuntimeDiagnostics.debug(
                "Skipping addTab for '\(tab.name)' because no spaceId was resolved.",
                category: "TabManager"
            )
            return false
        }
        guard membership.contains(tab) == false,
              let placement = regularTabs.preparePlacement(
                  tab,
                  in: spaceID,
                  at: regularInsertionIndex,
                  admissionProfileIDs: admissionProfileIDs
              ),
              placement.stage()
        else { return false }
        guard placement.finish(publishing: {
            membership.attach(tab)
            persistence.scheduleStructuralPersistence()
        }) else {
            precondition(placement.rollback())
            return false
        }
        return true
    }
}
