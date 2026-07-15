import Foundation

/// Owns post-WebKit publication after a Tab generation is irreversibly gone.
@MainActor
final class TabRuntimeTeardownPublisher {
    private let persistence: TabStructuralPersistenceService
    private let membership: TabCollectionMembershipOwner

    init(
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner
    ) {
        self.persistence = persistence
        self.membership = membership
    }

    @discardableResult
    func publish(
        _ tabs: [Tab],
        runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        let tabIDs = Set(tabs.map(\.id))
        guard tabIDs.isEmpty == false else { return [] }
        tabs.forEach {
            persistence.cancelRuntimeStatePersistence(for: $0.id)
        }
        let splitSettlement = runtime.stageTabClosures(tabIDs)

        for tab in tabs {
            removeAuxiliaryResidence(of: tab, runtime: runtime)
            runtime.notifyTabClosedIfLoaded(tab)
            runtime.webViewLifecycle.unloadTab(tab)
            membership.detach(tab)
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
        }
        splitSettlement?.publish()
        return tabIDs
    }

    private func removeAuxiliaryResidence(
        of tab: Tab,
        runtime: RuntimePortRegistry
    ) {
        if membership.isAuxiliaryMiniWindowTab(tab) {
            runtime.closeAuxiliaryMiniWindow(for: tab, reason: .bulkCleanup)
            if membership.isAuxiliaryMiniWindowTab(tab) {
                membership.removeAuxiliaryMiniWindowTab(tab)
            }
        } else if membership.isTransientExtensionTab(tab) {
            _ = membership.removeTransientExtensionTab(id: tab.id)
        }
    }
}
