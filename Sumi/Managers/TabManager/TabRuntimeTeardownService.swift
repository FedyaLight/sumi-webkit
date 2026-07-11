import Foundation

/// Ends live runtime ownership for a batch of tabs without mutating their
/// persisted structural containers. Callers remove those containers once,
/// after every tab has stopped producing runtime state.
@MainActor
final class TabRuntimeTeardownService {
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
    func teardown(
        _ tabs: [Tab],
        using runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        var seen = Set<UUID>()
        let uniqueTabs = tabs.filter { seen.insert($0.id).inserted }
        guard !uniqueTabs.isEmpty else { return [] }

        let tabIds = Set(uniqueTabs.map(\.id))
        uniqueTabs.forEach {
            persistence.cancelRuntimeStatePersistence(for: $0.id)
        }
        runtime.handleTabClosures(tabIds)

        for tab in uniqueTabs {
            if membership.isAuxiliaryMiniWindowTab(tab) {
                runtime.closeAuxiliaryMiniWindow(for: tab, reason: .bulkCleanup)
                if membership.isAuxiliaryMiniWindowTab(tab) == false {
                    continue
                }
                membership.removeAuxiliaryMiniWindowTab(tab)
            } else if membership.isTransientExtensionTab(tab) {
                _ = membership.removeTransientExtensionTab(id: tab.id)
            }

            runtime.notifyTabClosedIfLoaded(tab)
            tab.performComprehensiveWebViewCleanup()
            runtime.webViewLifecycle.unloadTab(tab)
            runtime.webViewLifecycle.requireRemoveAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
            membership.detach(tab)
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
        }
        return tabIds
    }
}
