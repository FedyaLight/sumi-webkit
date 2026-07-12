import Foundation

/// Releases runtime ownership for durable regular tabs that were already
/// removed from structural collections. Ordering is load-bearing: split
/// closure handling, selection-history scrub, WebView teardown, membership
/// detach, then lifecycle notification.
@MainActor
final class RegularTabClosureRuntimeCleanup {
    private let membership: TabCollectionMembershipOwner

    init(membership: TabCollectionMembershipOwner) {
        self.membership = membership
    }

    func releaseConfirmedRemovals(
        _ removals: [RegularTabCollectionOwner.Removal],
        runtime: RuntimePortRegistry
    ) {
        guard !removals.isEmpty else { return }

        let removedTabIDs = Set(removals.map(\.tab.id))
        runtime.handleTabClosures(removedTabIDs)

        for removal in removals {
            let tab = removal.tab
            runtime.notifyTabClosedIfLoaded(tab)

            runtime.forEachWindowState { windowState in
                windowState.selectionHistory
                    .removeFromRegularTabHistory(tab.id)
            }

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
    }
}
