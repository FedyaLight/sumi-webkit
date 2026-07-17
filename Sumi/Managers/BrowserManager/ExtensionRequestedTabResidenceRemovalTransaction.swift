import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabResidenceRemovalTransaction {
    private let membership: TabCollectionMembershipOwner
    private let transientTabs: TransientExtensionTabRetirementTransaction
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let persistence: TabStructuralPersistenceService

    init(
        membership: TabCollectionMembershipOwner,
        transientTabs: TransientExtensionTabRetirementTransaction,
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.membership = membership
        self.transientTabs = transientTabs
        self.regularTabs = regularTabs
        self.spaces = spaces
        self.persistence = persistence
    }

    func remove(
        _ tab: Tab,
        notifyingExtensionClose: Bool
    ) -> ExtensionRequestedTabRemoval? {
        guard membership.tab(for: tab.id) === tab else { return nil }
        persistence.cancelRuntimeStatePersistence(for: tab.id)
        if transientTabs.remove(
            id: tab.id,
            notifyingExtensionClose: notifyingExtensionClose
        ) {
            return .transient
        }
        let removals = regularTabs.remove(
            [tab.id],
            in: spaces.spaces,
            currentSpaceId: spaces.currentSpaceId
        )
        guard removals.count == 1,
              removals[0].tab === tab else { return nil }
        return .regular(tab)
    }
}
