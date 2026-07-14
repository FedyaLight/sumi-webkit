import Foundation

/// Publishes terminal runtime teardown after structural owners commit.
@MainActor
final class TabRuntimeTeardownService {
    private let persistence: TabStructuralPersistenceService
    private let membership: TabCollectionMembershipOwner
    let preparation: TabRuntimeTeardownPreparationService

    init(
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        preparation: TabRuntimeTeardownPreparationService = .init()
    ) {
        self.persistence = persistence
        self.membership = membership
        self.preparation = preparation
    }

    @discardableResult
    func teardown(
        _ tabs: [Tab],
        using runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        guard let prepared = preparation.prepare(tabs, using: runtime) else {
            return []
        }
        return finish(prepared)
    }

    /// Publishes the infallible terminal phase.
    @discardableResult
    func finish(_ prepared: PreparedTabRuntimeTeardown) -> Set<UUID> {
        let tabIds = prepared.tabIds
        guard tabIds.isEmpty == false else { return [] }
        prepared.tabs.forEach {
            persistence.cancelRuntimeStatePersistence(for: $0.id)
        }
        prepared.runtime.handleTabClosures(tabIds)

        for tab in prepared.tabs {
            if membership.isAuxiliaryMiniWindowTab(tab) {
                prepared.runtime.closeAuxiliaryMiniWindow(
                    for: tab,
                    reason: .bulkCleanup
                )
                if membership.isAuxiliaryMiniWindowTab(tab) == false {
                    continue
                }
                membership.removeAuxiliaryMiniWindowTab(tab)
            } else if membership.isTransientExtensionTab(tab) {
                _ = membership.removeTransientExtensionTab(id: tab.id)
            }

            prepared.runtime.notifyTabClosedIfLoaded(tab)
            prepared.runtime.webViewLifecycle.unloadTab(tab)
            membership.detach(tab)
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
        }
        return tabIds
    }
}
